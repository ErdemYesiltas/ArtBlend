import AVFoundation
import Cocoa
import CoreGraphics
import FlutterMacOS
import ImageIO

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Time-lapse export: encoding takes a while, off the main thread.
    let video = FlutterMethodChannel(
      name: "artblend/video", binaryMessenger: flutterViewController.engine.binaryMessenger)
    video.setMethodCallHandler { call, result in
      guard call.method == "encode", let args = call.arguments as? [String: Any],
        let frames = args["frames"] as? [String], let output = args["output"] as? String,
        let width = args["width"] as? Int, let height = args["height"] as? Int
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let fps = args["fps"] as? Int ?? 30
      let alpha = args["alpha"] as? Bool ?? false
      let audio = args["audio"] as? String
      DispatchQueue.global(qos: .userInitiated).async {
        let ok = VideoEncoder.encode(
          frames: frames, output: output, width: width, height: height, fps: fps, alpha: alpha,
          audio: audio)
        DispatchQueue.main.async { result(ok) }
      }
    }

    // Movie media: reading and decoding take a while, off the main thread.
    let media = FlutterMethodChannel(
      name: "artblend/media", binaryMessenger: flutterViewController.engine.binaryMessenger)
    media.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let value: Any?
        switch call.method {
        case "probe": value = MediaTools.probe(path)
        case "frames":
          value = MediaTools.frames(
            path, out: args["out"] as? String ?? "", fps: args["fps"] as? Double ?? 30,
            maxSide: args["maxSide"] as? Int ?? 640)
        case "audio": value = MediaTools.audio(path, out: args["out"] as? String ?? "")
        case "pdfPages":
          value = MediaTools.pdfPages(
            path, out: args["out"] as? String ?? "", maxSide: args["maxSide"] as? Int ?? 4096)
        default: value = FlutterMethodNotImplemented
        }
        DispatchQueue.main.async { result(value) }
      }
    }
    let audio = FlutterMethodChannel(
      name: "artblend/audio", binaryMessenger: flutterViewController.engine.binaryMessenger)
    audio.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "play":
        MediaTools.play(
          args["path"] as? String ?? "", offsetMs: args["offsetMs"] as? Int ?? 0,
          lengthMs: args["lengthMs"] as? Int)
      case "stop": MediaTools.stop()
      case "position":
        result(MediaTools.position())
        return
      case "release": MediaTools.release()
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(true)
    }

    super.awakeFromNib()
  }
}

/// Movie media: what a file holds, its pictures as small JPEG proxies, its
/// sound as 48 kHz stereo 16-bit WAV, and playing a WAV.
enum MediaTools {
  static func probe(_ path: String) -> [String: Any]? {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let sem = DispatchSemaphore(value: 0)
    var out: [String: Any]?
    Task {
      defer { sem.signal() }
      guard let duration = try? await asset.load(.duration) else { return }
      let videos = (try? await asset.loadTracks(withMediaType: .video)) ?? []
      let audios = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
      var width = 0.0, height = 0.0, fps = 30.0
      if let v = videos.first,
        let size = try? await v.load(.naturalSize),
        let transform = try? await v.load(.preferredTransform)
      {
        let r = CGRect(origin: .zero, size: size).applying(transform)
        width = abs(r.width)
        height = abs(r.height)
        if let rate = try? await v.load(.nominalFrameRate), rate > 0 { fps = Double(rate) }
      }
      out = [
        "width": Int(width), "height": Int(height),
        "durationMs": Int(duration.seconds * 1000), "fps": fps,
        "hasVideo": !videos.isEmpty, "hasAudio": !audios.isEmpty,
      ]
    }
    sem.wait()
    return out
  }

  static func frames(_ path: String, out: String, fps: Double, maxSide: Int) -> Int {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    try? FileManager.default.createDirectory(
      atPath: out, withIntermediateDirectories: true)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.maximumSize = CGSize(width: maxSide, height: maxSide)
    let seconds = asset.duration.seconds
    guard seconds.isFinite, seconds > 0 else { return 0 }
    let count = max(1, Int(seconds * fps))
    var written = 0
    for i in 0..<count {
      let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
      guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
      let url = URL(fileURLWithPath: out).appendingPathComponent(String(format: "%05d.jpg", i))
      guard
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
      else { continue }
      CGImageDestinationAddImage(
        dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
      if CGImageDestinationFinalize(dest) { written = i + 1 }
    }
    return written
  }

  static func audio(_ path: String, out: String) -> Bool {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: .audio).first,
      let reader = try? AVAssetReader(asset: asset)
    else { return false }
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])
    guard reader.canAdd(output) else { return false }
    reader.add(output)
    guard reader.startReading() else { return false }
    var pcm = Data()
    while let buffer = output.copyNextSampleBuffer() {
      if let block = CMSampleBufferGetDataBuffer(buffer) {
        let length = CMBlockBufferGetDataLength(block)
        var bytes = Data(count: length)
        bytes.withUnsafeMutableBytes { raw in
          _ = CMBlockBufferCopyDataBytes(
            block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        pcm.append(bytes)
      }
    }
    guard reader.status == .completed else { return false }
    var header = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; header.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; header.append(Data(bytes: &x, count: 2)) }
    header.append("RIFF".data(using: .ascii)!)
    u32(UInt32(36 + pcm.count))
    header.append("WAVEfmt ".data(using: .ascii)!)
    u32(16); u16(1); u16(2); u32(48000); u32(48000 * 4); u16(4); u16(16)
    header.append("data".data(using: .ascii)!)
    u32(UInt32(pcm.count))
    return (try? (header + pcm).write(to: URL(fileURLWithPath: out))) != nil
  }

  /// Every page of the PDF at [path] drawn (vectors and all) on white, at
  /// most [maxSide] pixels across, as `out/page000.png` …; their paths.
  static func pdfPages(_ path: String, out: String, maxSide: Int) -> [String] {
    guard let doc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL) else { return [] }
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var paths: [String] = []
    for i in 0..<doc.numberOfPages {
      guard let page = doc.page(at: i + 1) else { continue }
      let box = page.getBoxRect(.cropBox)
      let scale = Double(maxSide) / max(box.width, box.height)
      let w = max(1, Int(box.width * scale)), h = max(1, Int(box.height * scale))
      guard
        let ctx = CGContext(
          data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { continue }
      ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
      ctx.interpolationQuality = .high
      ctx.scaleBy(x: scale, y: scale)
      ctx.translateBy(x: -box.minX, y: -box.minY)
      ctx.drawPDFPage(page)
      guard let image = ctx.makeImage() else { continue }
      let url = URL(fileURLWithPath: out).appendingPathComponent(String(format: "page%03d.png", i))
      guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
      else { continue }
      CGImageDestinationAddImage(dest, image, nil)
      if CGImageDestinationFinalize(dest) { paths.append(url.path) }
    }
    return paths
  }

  private static var player: AVAudioPlayer?
  private static var playing: String?
  private static var stopper: DispatchWorkItem?

  static func play(_ path: String, offsetMs: Int, lengthMs: Int?) {
    if playing != path || player == nil {
      player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      playing = path
      player?.prepareToPlay()
    }
    guard let p = player else { return }
    stopper?.cancel()
    p.currentTime = Double(offsetMs) / 1000
    p.play()
    if let length = lengthMs {
      let work = DispatchWorkItem { p.pause() }
      stopper = work
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(length), execute: work)
    }
  }

  static func stop() { player?.pause() }

  /// Where the sound is now (ms), while it plays.
  static func position() -> Int? {
    guard let p = player, p.isPlaying else { return nil }
    return Int(p.currentTime * 1000)
  }

  static func release() {
    player?.stop()
    player = nil
    playing = nil
  }
}

/// Frames (image files, in order) into an H.264 MP4 on white, or with
/// [alpha] into a QuickTime HEVC that keeps transparency; each frame shown
/// 1/fps second.
enum VideoEncoder {
  static func encode(
    frames: [String], output: String, width: Int, height: Int, fps: Int, alpha: Bool = false,
    audio: String? = nil
  ) -> Bool {
    guard !frames.isEmpty, width >= 2, height >= 2, fps > 0 else { return false }
    let url = URL(fileURLWithPath: output)
    try? FileManager.default.removeItem(at: url)
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: alpha ? .mov : .mp4) else {
      return false
    }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: alpha ? AVVideoCodecType.hevcWithAlpha : AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    guard writer.canAdd(input) else { return false }
    writer.add(input)
    // The sound (a WAV) as AAC, written alongside on a queue of its own:
    // the writer interleaves the two and waits for both.
    var sound: (AVAssetWriterInput, AVAssetReader, AVAssetReaderTrackOutput)?
    let soundAsset = audio.map { AVURLAsset(url: URL(fileURLWithPath: $0)) }
    if let soundAsset,
      let track = soundAsset.tracks(withMediaType: .audio).first,
      let reader = try? AVAssetReader(asset: soundAsset)
    {
      let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
          AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
          AVLinearPCMIsBigEndianKey: false,
        ])
      let aac = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
          AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000,
        ])
      if reader.canAdd(output), writer.canAdd(aac) {
        reader.add(output)
        writer.add(aac)
        sound = (aac, reader, output)
      }
    }
    guard writer.startWriting() else { return false }
    writer.startSession(atSourceTime: .zero)
    let soundDone = DispatchGroup()
    if let (aac, reader, output) = sound, reader.startReading() {
      soundDone.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        while let buffer = output.copyNextSampleBuffer() {
          while !aac.isReadyForMoreMediaData { usleep(1000) }
          aac.append(buffer)
        }
        aac.markAsFinished()
        soundDone.leave()
      }
    } else if let (aac, _, _) = sound {
      aac.markAsFinished()
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var written = 0
    for path in frames {
      guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { continue }
      while !input.isReadyForMoreMediaData { usleep(1000) }
      guard let pool = adaptor.pixelBufferPool else { break }
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
      guard let pixels = buffer else { continue }
      CVPixelBufferLockBaseAddress(pixels, [])
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
      if alpha {
        context?.clear(CGRect(x: 0, y: 0, width: width, height: height))
      } else {
        context?.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
      }
      context?.interpolationQuality = .high
      context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      CVPixelBufferUnlockBaseAddress(pixels, [])
      if adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(fps))) {
        written += 1
      }
    }
    input.markAsFinished()
    soundDone.wait()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    return written > 0 && writer.status == .completed
  }
}
