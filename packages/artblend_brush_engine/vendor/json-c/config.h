/* ArtBlend portable configuration: Apple and Android Clang targets. */
#pragma once
#define HAVE_DLFCN_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_CDEFS_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAVE_ATOMIC_BUILTINS 1
#define HAVE_DECL_INFINITY 1
#define HAVE_DECL_ISINF 1
#define HAVE_DECL_ISNAN 1
#define HAVE_DECL_NAN 1
#define HAVE_OPEN 1
#define HAVE_REALLOC 1
#define HAVE_SETLOCALE 1
#define HAVE_SNPRINTF 1
#define HAVE_STRCASECMP 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRNCASECMP 1
#define HAVE_USELOCALE 1
#define HAVE_DUPLOCALE 1
#define HAVE_VASPRINTF 1
#define HAVE_VPRINTF 1
#define HAVE_VSNPRINTF 1
#define HAVE_GETRUSAGE 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOULL 1
#define HAVE____THREAD 1
#define STDC_HEADERS 1
#define JSON_C_HAVE_INTTYPES_H 1
#define SIZEOF_INT __SIZEOF_INT__
#define SIZEOF_INT64_T 8
#define SIZEOF_LONG __SIZEOF_LONG__
#define SIZEOF_LONG_LONG __SIZEOF_LONG_LONG__
#define SIZEOF_SIZE_T __SIZEOF_SIZE_T__
#define SIZEOF_SSIZE_T __SIZEOF_SIZE_T__
#define SPEC___THREAD __thread
#define PACKAGE "json-c"
#define VERSION "0.19"
#if defined(__APPLE__)
#define HAVE_XLOCALE_H 1
#define HAVE_ARC4RANDOM 1
#elif defined(__ANDROID__)
#define HAVE_ENDIAN_H 1
#endif
