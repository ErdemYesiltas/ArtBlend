#include "artblend_brush_engine.h"
#include "mypaint-brush.h"
#include "mypaint-brush-settings.h"
#include "mypaint-tiled-surface.h"
#include "json.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#define TILE 64
#define CHANNELS (TILE * TILE * 4)
#define ONE 32768u

/* Single worker ownership; no OpenMP. Tiles allocate only on write. */
/* One stamp path per symmetric copy; copies share the stroke's coverage. */
typedef struct {
    int has_last;
    float last_x, last_y, last_p, remain, direction;
    uint32_t rng;
    /* Smudge: where the previous dab of this path landed. */
    int has_dab;
    float dab_x, dab_y;
    /* Dual brush: the secondary tip's distance to its next dab. */
    float remain2;
    /* Wet mix: the colour on the brush (0-1) and how far it has painted. */
    float res[3], travel;
} StampTrack;

struct ABBrushSurface {
    MyPaintTiledSurface parent;
    /* One brush per symmetric copy; [0] is the stroke as drawn. */
    MyPaintBrush *brushes[AB_MAX_COPIES];
    int copies;
    float sym[AB_MAX_COPIES][4], sym_cx, sym_cy;
    StampTrack tracks[AB_MAX_COPIES];
    uint16_t **tiles;
    uint8_t *dirty; /* tiles written by dabs since the last ab_surface_take_dirty */
    uint16_t empty[CHANNELS];
    int width, height, columns, rows, allocated, failed;
    float preset_opaque; /* the loaded preset's own opacity, scaled by configure */
    float preset_smudge, preset_smudge_length; /* the preset's own, restored after smudging */
    int smudging;
    /* Stamp brush: active after ab_stamp_load until the next ab_brush_load. */
    int stamping;
    uint8_t *tip, *grain;
    int tip_w, tip_h, grain_w, grain_h;
    float st[AB_STAMP_PARAMS];
    float diameter, rgb[3], opacity;
    int eraser;
    /* Stroke state: tiles as they were before the stroke (NULL when empty),
     * and the coverage the stroke built up, both per touched tile. */
    uint16_t **orig, **mask;
    /* Dual brush: the secondary tip, its settings and its own coverage. */
    int dual;
    uint8_t *tip2;
    int tip2_w, tip2_h;
    float dp[AB_DUAL_PARAMS];
    uint16_t **mask2;
    /* Wet mix: dilution, charge, pull; the stroke's own paint (premultiplied
     * RGBA per touched tile), which dabs of changing colour build up. */
    int wet;
    float wp[3];
    uint16_t **paint;
    uint8_t *saved;
    uint32_t strokes;
};
enum { SP_SPACING, SP_SCATTER, SP_SIZE_JITTER, SP_OPACITY_JITTER, SP_ROTATION,
    SP_ROTATION_JITTER, SP_FOLLOW, SP_PRESSURE_SIZE, SP_PRESSURE_OPACITY, SP_FLOW,
    SP_GRAIN_DEPTH, SP_GRAIN_SCALE };
static void tile_start(MyPaintTiledSurface *parent, MyPaintTileRequest *r) {
    ABBrushSurface *s = (ABBrushSurface *)parent;
    if (r->tx < 0 || r->ty < 0 || r->tx >= s->columns || r->ty >= s->rows) {
        memset(s->empty, 0, sizeof(s->empty)); r->buffer = s->empty; return;
    }
    uint16_t **t = &s->tiles[r->ty * s->columns + r->tx];
    if (!r->readonly) s->dirty[r->ty * s->columns + r->tx] = 1;
    if (!*t && !r->readonly) {
        *t = calloc(CHANNELS, sizeof(uint16_t));
        if (*t) s->allocated++; else s->failed = 1;
    }
    if (*t) r->buffer = *t;
    else { memset(s->empty, 0, sizeof(s->empty)); r->buffer = s->empty; }
}
static void tile_end(MyPaintTiledSurface *p, MyPaintTileRequest *r) { (void)p; (void)r; }
const char *ab_engine_version(void) { return "libmypaint-1.6.1/artblend-6"; }
ABBrushSurface *ab_surface_create(int w, int h) {
    if (w < 1 || h < 1 || w > 4096 || h > 4096) return NULL;
    ABBrushSurface *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->width=w; s->height=h; s->columns=(w+TILE-1)/TILE; s->rows=(h+TILE-1)/TILE;
    s->tiles=calloc((size_t)s->columns*s->rows,sizeof(uint16_t*));
    s->dirty=calloc((size_t)s->columns*s->rows,1);
    s->orig=calloc((size_t)s->columns*s->rows,sizeof(uint16_t*));
    s->mask=calloc((size_t)s->columns*s->rows,sizeof(uint16_t*));
    s->mask2=calloc((size_t)s->columns*s->rows,sizeof(uint16_t*));
    s->paint=calloc((size_t)s->columns*s->rows,sizeof(uint16_t*));
    s->saved=calloc((size_t)s->columns*s->rows,1);
    if (!s->tiles||!s->dirty||!s->orig||!s->mask||!s->mask2||!s->paint||!s->saved) {
        free(s->tiles); free(s->dirty); free(s->orig); free(s->mask); free(s->mask2); free(s->paint); free(s->saved); free(s); return NULL;
    }
    s->diameter=8; s->opacity=1;
    for (int i=0;i<AB_MAX_COPIES;i++) {
        s->brushes[i]=mypaint_brush_new();
        if (!s->brushes[i]) {
            for (int j=0;j<i;j++) mypaint_brush_unref(s->brushes[j]);
            free(s->tiles); free(s->dirty); free(s->orig); free(s->mask); free(s->mask2); free(s->paint); free(s->saved); free(s); return NULL;
        }
        mypaint_brush_from_defaults(s->brushes[i]);
    }
    s->copies=1; s->sym[0][0]=1; s->sym[0][3]=1;
    s->preset_smudge=mypaint_brush_get_base_value(s->brushes[0],MYPAINT_BRUSH_SETTING_SMUDGE);
    s->preset_smudge_length=mypaint_brush_get_base_value(s->brushes[0],MYPAINT_BRUSH_SETTING_SMUDGE_LENGTH);
    s->preset_opaque=mypaint_brush_get_base_value(s->brushes[0],MYPAINT_BRUSH_SETTING_OPAQUE);
    mypaint_tiled_surface_init(&s->parent,tile_start,tile_end);
    s->parent.threadsafe_tile_requests=FALSE;
    return s;
}
void ab_surface_destroy(ABBrushSurface *s) {
    if (!s) return;
    mypaint_tiled_surface_destroy(&s->parent);
    for(int i=0;i<AB_MAX_COPIES;i++) mypaint_brush_unref(s->brushes[i]);
    for(int i=0;i<s->columns*s->rows;i++) { free(s->tiles[i]); free(s->orig[i]); free(s->mask[i]); free(s->mask2[i]); free(s->paint[i]); }
    free(s->tiles); free(s->dirty); free(s->orig); free(s->mask); free(s->mask2); free(s->paint); free(s->saved);
    free(s->tip); free(s->grain); free(s->tip2); free(s);
}
static int numeric(json_object *o) {
    return o && (json_object_is_type(o,json_type_double)||json_object_is_type(o,json_type_int)) && isfinite(json_object_get_double(o));
}
/* Reduce a preset to what libmypaint can safely read, the way MyPaint itself
 * tolerates real-world brush files: settings and inputs this version does not
 * know are skipped, base values are clamped to their documented range, and
 * curve points that are not finite, too large or not strictly increasing in x
 * are dropped (a curve needs two). This still guards upstream's 64-element
 * mapping arrays and negative enum lookups. Rejects only a file that is not
 * version 3 JSON or keeps no usable setting. */
#define AB_MAX_KEYS 256
static int sanitize_preset(json_object *root) {
    json_object *version,*settings;
    if (!json_object_is_type(root,json_type_object) ||
        !json_object_object_get_ex(root,"version",&version) ||
        !json_object_is_type(version,json_type_int) || json_object_get_int(version)!=3 ||
        !json_object_object_get_ex(root,"settings",&settings) ||
        !json_object_is_type(settings,json_type_object) ||
        json_object_object_length(settings)<1 || json_object_object_length(settings)>AB_MAX_KEYS) return 0;
    char *names[AB_MAX_KEYS]; int count=0;
    json_object_object_foreach(settings,name,unused) { (void)unused; names[count++]=name; }
    int kept=0;
    for (int k=0;k<count;k++) {
        json_object *setting,*base,*inputs;
        int id=mypaint_brush_setting_from_cname(names[k]);
        if (!json_object_object_get_ex(settings,names[k],&setting) ||
            id<0 || id>=MYPAINT_BRUSH_SETTINGS_COUNT || !json_object_is_type(setting,json_type_object) ||
            !json_object_object_get_ex(setting,"base_value",&base) || !numeric(base)) {
            json_object_object_del(settings,names[k]); continue;
        }
        const MyPaintBrushSettingInfo *info=mypaint_brush_setting_info(id);
        double b=json_object_get_double(base);
        if (b<info->min) b=info->min;
        if (b>info->max) b=info->max;
        json_object_object_add(setting,"base_value",json_object_new_double(b));
        if (!json_object_object_get_ex(setting,"inputs",&inputs) || !json_object_is_type(inputs,json_type_object) ||
            json_object_object_length(inputs)>AB_MAX_KEYS) {
            json_object_object_add(setting,"inputs",json_object_new_object());
            kept++; continue;
        }
        char *input_names[AB_MAX_KEYS]; int input_count=0;
        json_object_object_foreach(inputs,input_name,unused_points) { (void)unused_points; input_names[input_count++]=input_name; }
        for (int i=0;i<input_count;i++) {
            json_object *points;
            int input=mypaint_brush_input_from_cname(input_names[i]);
            if (!json_object_object_get_ex(inputs,input_names[i],&points) ||
                input<0 || input>=MYPAINT_BRUSH_INPUTS_COUNT || !json_object_is_type(points,json_type_array)) {
                json_object_object_del(inputs,input_names[i]); continue;
            }
            json_object *clean=json_object_new_array();
            double previous=-INFINITY;
            size_t n=json_object_array_length(points);
            for (size_t p=0;p<n && json_object_array_length(clean)<64;p++) {
                json_object *pt=json_object_array_get_idx(points,p);
                if (!json_object_is_type(pt,json_type_array) || json_object_array_length(pt)!=2) continue;
                json_object *x=json_object_array_get_idx(pt,0),*y=json_object_array_get_idx(pt,1);
                if (!numeric(x)||!numeric(y)) continue;
                double xx=json_object_get_double(x),yy=json_object_get_double(y);
                if (xx<=previous || fabs(xx)>10000 || fabs(yy)>10000) continue;
                previous=xx;
                json_object *pair=json_object_new_array();
                json_object_array_add(pair,json_object_new_double(xx));
                json_object_array_add(pair,json_object_new_double(yy));
                json_object_array_add(clean,pair);
            }
            if (json_object_array_length(clean)<2) {
                json_object_put(clean);
                json_object_object_del(inputs,input_names[i]);
            } else {
                json_object_object_add(inputs,input_names[i],clean);
            }
        }
        kept++;
    }
    return kept>0;
}
int ab_brush_load(ABBrushSurface *s,const char *json,size_t length) {
    if(!s||!json||!length||length>1024*1024||memchr(json,0,length)) return 0;
    struct json_tokener *tok=json_tokener_new_ex(32);
    if(!tok) return 0;
    json_tokener_set_flags(tok,JSON_TOKENER_STRICT|JSON_TOKENER_VALIDATE_UTF8);
    json_object *root=json_tokener_parse_ex(tok,json,(int)length);
    int valid=json_tokener_get_error(tok)==json_tokener_success && json_tokener_get_parse_end(tok)==length && sanitize_preset(root);
    json_tokener_free(tok);
    if(!valid) { json_object_put(root); return 0; }
    const char *text=json_object_to_json_string_ext(root,JSON_C_TO_STRING_PLAIN);
    MyPaintBrush *loaded[AB_MAX_COPIES]={0};
    int ok=1;
    for(int i=0;i<AB_MAX_COPIES&&ok;i++) {
        loaded[i]=mypaint_brush_new();
        if(!loaded[i]) { ok=0; break; }
        mypaint_brush_from_defaults(loaded[i]);
        ok=mypaint_brush_from_string(loaded[i],text);
    }
    json_object_put(root);
    if(!ok) {
        for(int i=0;i<AB_MAX_COPIES;i++) if(loaded[i]) mypaint_brush_unref(loaded[i]);
        return 0;
    }
    for(int i=0;i<AB_MAX_COPIES;i++) { mypaint_brush_unref(s->brushes[i]); s->brushes[i]=loaded[i]; }
    s->preset_opaque=mypaint_brush_get_base_value(s->brushes[0],MYPAINT_BRUSH_SETTING_OPAQUE);
    s->preset_smudge=mypaint_brush_get_base_value(s->brushes[0],MYPAINT_BRUSH_SETTING_SMUDGE);
    s->preset_smudge_length=mypaint_brush_get_base_value(s->brushes[0],MYPAINT_BRUSH_SETTING_SMUDGE_LENGTH);
    s->stamping=0;
    if(s->smudging) ab_brush_smudge(s,1);
    return 1;
}
int ab_brush_configure(ABBrushSurface *s,float diameter,float hue,float saturation,float value,float opacity,int eraser) {
    if(!s||!isfinite(diameter)||diameter<1||diameter>256||!isfinite(hue)||hue<0||hue>1||
       !isfinite(saturation)||saturation<0||saturation>1||!isfinite(value)||value<0||value>1||!isfinite(opacity)||opacity<0||opacity>1) return 0;
    for(int i=0;i<AB_MAX_COPIES;i++) {
    MyPaintBrush *brush=s->brushes[i];
    mypaint_brush_set_base_value(brush,MYPAINT_BRUSH_SETTING_RADIUS_LOGARITHMIC,logf(diameter/2));
    mypaint_brush_set_base_value(brush,MYPAINT_BRUSH_SETTING_COLOR_H,hue);
    mypaint_brush_set_base_value(brush,MYPAINT_BRUSH_SETTING_COLOR_S,saturation);
    mypaint_brush_set_base_value(brush,MYPAINT_BRUSH_SETTING_COLOR_V,value);
    /* Scale the preset's opacity; opaque_multiply usually carries its pressure curve. */
    mypaint_brush_set_base_value(brush,MYPAINT_BRUSH_SETTING_OPAQUE,s->preset_opaque*opacity);
    mypaint_brush_set_base_value(brush,MYPAINT_BRUSH_SETTING_ERASER,eraser?1:0);
    }
    float h=hue*6, f=h-floorf(h), p=value*(1-saturation), q=value*(1-f*saturation), t=value*(1-(1-f)*saturation);
    float r,g,b;
    switch(((int)h)%6) {
        case 0: r=value; g=t; b=p; break;
        case 1: r=q; g=value; b=p; break;
        case 2: r=p; g=value; b=t; break;
        case 3: r=p; g=q; b=value; break;
        case 4: r=t; g=p; b=value; break;
        default: r=value; g=p; b=q; break;
    }
    s->rgb[0]=r; s->rgb[1]=g; s->rgb[2]=b;
    s->diameter=diameter; s->opacity=opacity; s->eraser=eraser!=0;
    return 1;
}

/* ---- Stamp brushes ---- */

#define AB_PI 3.14159265f
static uint16_t *pixel(ABBrushSurface *s,int x,int y,int allocate);

static int in_range(float v,float lo,float hi) { return isfinite(v)&&v>=lo&&v<=hi; }
int ab_stamp_load(ABBrushSurface *s,const uint8_t *tip,int tw,int th,const uint8_t *grain,int gw,int gh,const float *p,int count) {
    if(!s||!tip||tw<1||th<1||tw>512||th>512||!p||count!=AB_STAMP_PARAMS) return 0;
    if(grain&&(gw<1||gh<1||gw>1024||gh>1024)) return 0;
    if(!in_range(p[SP_SPACING],.01f,4)||!in_range(p[SP_SCATTER],0,4)||!in_range(p[SP_SIZE_JITTER],0,1)||
       !in_range(p[SP_OPACITY_JITTER],0,1)||!in_range(p[SP_ROTATION],-360,360)||!in_range(p[SP_ROTATION_JITTER],0,1)||
       !in_range(p[SP_FOLLOW],0,1)||!in_range(p[SP_PRESSURE_SIZE],0,1)||!in_range(p[SP_PRESSURE_OPACITY],0,1)||
       !in_range(p[SP_FLOW],.01f,1)||!in_range(p[SP_GRAIN_DEPTH],0,1)||!in_range(p[SP_GRAIN_SCALE],.1f,8)) return 0;
    uint8_t *t=malloc((size_t)tw*th), *g=grain?malloc((size_t)gw*gh):NULL;
    if(!t||(grain&&!g)) { free(t); free(g); return 0; }
    memcpy(t,tip,(size_t)tw*th);
    if(g) memcpy(g,grain,(size_t)gw*gh);
    free(s->tip); free(s->grain);
    s->tip=t; s->tip_w=tw; s->tip_h=th;
    s->grain=g; s->grain_w=g?gw:0; s->grain_h=g?gh:0;
    memcpy(s->st,p,sizeof(s->st));
    s->stamping=1;
    /* A new brush is single and dry until told otherwise. */
    s->dual=0;
    s->wet=0;
    return 1;
}
enum { WP_DILUTION, WP_CHARGE, WP_PULL };
int ab_stamp_wet(ABBrushSurface *s,float dilution,float charge,float pull) {
    if(!s||!in_range(dilution,0,1)||!in_range(charge,.01f,1)||!in_range(pull,0,1)) return 0;
    s->wp[WP_DILUTION]=dilution; s->wp[WP_CHARGE]=charge; s->wp[WP_PULL]=pull;
    s->wet=dilution>0||charge<1||pull>0;
    return 1;
}
enum { DP_MODE, DP_SIZE, DP_SPACING, DP_SCATTER, DP_SIZE_JITTER, DP_ROTATION_JITTER, DP_FOLLOW };
int ab_stamp_dual(ABBrushSurface *s,const uint8_t *tip,int tw,int th,const float *p,int count) {
    if(!s) return 0;
    if(!tip) { s->dual=0; return 1; }
    if(tw<1||th<1||tw>512||th>512||!p||count!=AB_DUAL_PARAMS) return 0;
    if(!isfinite(p[DP_MODE])||p[DP_MODE]<0||p[DP_MODE]>=AB_DUAL_MODES||
       !in_range(p[DP_SIZE],.05f,4)||!in_range(p[DP_SPACING],.01f,4)||!in_range(p[DP_SCATTER],0,4)||
       !in_range(p[DP_SIZE_JITTER],0,1)||!in_range(p[DP_ROTATION_JITTER],0,1)||!in_range(p[DP_FOLLOW],0,1)) return 0;
    uint8_t *t=malloc((size_t)tw*th);
    if(!t) return 0;
    memcpy(t,tip,(size_t)tw*th);
    free(s->tip2);
    s->tip2=t; s->tip2_w=tw; s->tip2_h=th;
    memcpy(s->dp,p,sizeof(s->dp));
    s->dual=1;
    return 1;
}
/* How the secondary brush's coverage [b] combines with the primary's [a]
 * (0-1), as blend modes do with colours: 0 nowhere stays 0. */
static float combine(int mode,float a,float b) {
    switch(mode) {
    case 0: return a*b;                                   /* multiply */
    case 1: return fminf(a,b);                            /* darken */
    case 2: return fmaxf(a,b);                            /* lighten */
    case 3: return a+b-a*b;                               /* screen */
    case 4: return fminf(1,a+b);                          /* add */
    case 5: return fmaxf(0,a-b);                          /* subtract */
    case 6: return fabsf(a-b);                            /* difference */
    case 7: return a<.5f?2*a*b:1-2*(1-a)*(1-b);           /* overlay */
    case 8: return b<=0?0:fmaxf(0,1-(1-a)/b);             /* colour burn */
    case 9: return b>=1?(a>0?1:0):fminf(1,a/(1-b));       /* colour dodge */
    case 10: return fmaxf(0,a+b-1);                       /* linear burn */
    default: return a+b>=1&&a+b>0?1:0;                    /* hard mix */
    }
}
static float rnd(StampTrack *t) { /* xorshift32, [0,1) */
    uint32_t x=t->rng; x^=x<<13; x^=x>>17; x^=x<<5; t->rng=x;
    return (x>>8)*(1.0f/16777216.0f);
}
static void stamp_begin(ABBrushSurface *s) {
    size_t n=(size_t)s->columns*s->rows;
    for(size_t i=0;i<n;i++) {
        free(s->orig[i]); s->orig[i]=NULL; free(s->mask[i]); s->mask[i]=NULL; free(s->mask2[i]); s->mask2[i]=NULL;
        free(s->paint[i]); s->paint[i]=NULL;
    }
    memset(s->saved,0,n);
    /* Copies start from the same seed: mirrored dabs jitter alike. */
    uint32_t seed=0x9E3779B9u^(++s->strokes*2654435761u);
    if(!seed) seed=1;
    for(int i=0;i<AB_MAX_COPIES;i++) {
        StampTrack *t=&s->tracks[i];
        t->has_last=0; t->remain=0; t->direction=0; t->rng=seed; t->has_dab=0; t->remain2=0;
        t->travel=0; memcpy(t->res,s->rgb,sizeof(t->res));
    }
}
static float sample(const uint8_t *img,int w,int h,float x,float y,int wrap) {
    float fx=floorf(x), fy=floorf(y);
    int x0=(int)fx, y0=(int)fy;
    float ax=x-fx, ay=y-fy, v[4];
    for(int k=0;k<4;k++) {
        int xx=x0+(k&1), yy=y0+(k>>1);
        if(wrap) { xx%=w; if(xx<0) xx+=w; yy%=h; if(yy<0) yy+=h; }
        else if(xx<0||yy<0||xx>=w||yy>=h) { v[k]=0; continue; }
        v[k]=img[(size_t)yy*w+xx];
    }
    return ((v[0]*(1-ax)+v[1]*ax)*(1-ay)+(v[2]*(1-ax)+v[3]*ax)*ay)*(1.0f/255);
}
/* Premultiplied pixel at a fractional position, bilinear; outside or
 * unallocated reads as transparent. */
static void read_bilinear(ABBrushSurface *s,float x,float y,float out[4]) {
    float fx=floorf(x-.5f), fy=floorf(y-.5f), ax=x-.5f-fx, ay=y-.5f-fy;
    for(int c=0;c<4;c++) out[c]=0;
    for(int k=0;k<4;k++) {
        int xx=(int)fx+(k&1), yy=(int)fy+(k>>1);
        if(xx<0||yy<0||xx>=s->width||yy>=s->height) continue;
        uint16_t *p=pixel(s,xx,yy,0);
        if(!p) continue;
        float w=((k&1)?ax:1-ax)*((k>>1)?ay:1-ay);
        for(int c=0;c<4;c++) out[c]+=p[c]*w;
    }
}
/* Smudge: drags the pixels under the previous dab of the path to this one,
 * weighted by the tip, the grain and [alpha] (the strength). */
static void smudge_dab(ABBrushSurface *s,StampTrack *t,float cx,float cy,float size,float angle,float alpha) {
    if(!t->has_dab) { t->has_dab=1; t->dab_x=cx; t->dab_y=cy; return; }
    float mx=cx-t->dab_x, my=cy-t->dab_y;
    t->dab_x=cx; t->dab_y=cy;
    float scale=size/(float)(s->tip_w>s->tip_h?s->tip_w:s->tip_h);
    float extent=size*.7072f+1;
    int x0=(int)floorf(cx-extent), x1=(int)ceilf(cx+extent), y0=(int)floorf(cy-extent), y1=(int)ceilf(cy+extent);
    if(x0<0) x0=0;
    if(y0<0) y0=0;
    if(x1>s->width) x1=s->width;
    if(y1>s->height) y1=s->height;
    if(x1<=x0||y1<=y0) return;
    int w=x1-x0, h=y1-y0;
    /* Read every source first: this dab must not smear its own writes. */
    float *src=malloc((size_t)w*h*4*sizeof(float));
    if(!src) { s->failed=1; return; }
    for(int py=y0;py<y1;py++) for(int px=x0;px<x1;px++)
        read_bilinear(s,px+.5f-mx,py+.5f-my,src+((size_t)(py-y0)*w+(px-x0))*4);
    float ca=cosf(angle), sa=sinf(angle), depth=s->st[SP_GRAIN_DEPTH], gscale=s->st[SP_GRAIN_SCALE];
    for(int py=y0;py<y1&&!s->failed;py++) for(int px=x0;px<x1;px++) {
        float dx=px+.5f-cx, dy=py+.5f-cy;
        float u=(dx*ca+dy*sa)/scale+s->tip_w*.5f-.5f, v=(-dx*sa+dy*ca)/scale+s->tip_h*.5f-.5f;
        if(u<-1||v<-1||u>s->tip_w||v>s->tip_h) continue;
        float c=sample(s->tip,s->tip_w,s->tip_h,u,v,0)*alpha;
        if(s->grain&&depth>0) c*=1-depth+depth*sample(s->grain,s->grain_w,s->grain_h,px/gscale,py/gscale,1);
        if(c<=1.0f/ONE) continue;
        const float *from=src+((size_t)(py-y0)*w+(px-x0))*4;
        uint16_t *out=pixel(s,px,py,from[3]>0);
        if(!out) { if(s->failed) break; continue; }
        s->dirty[(py/TILE)*s->columns+px/TILE]=1;
        for(int k=0;k<4;k++) {
            float v2=out[k]+(from[k]-out[k])*c;
            out[k]=(uint16_t)(v2<0?0:v2>ONE?ONE:v2+.5f);
        }
    }
    free(src);
}
/* One dab of the primary tip, or with [second] of the dual brush's
 * secondary tip: it builds up its own coverage, and each pixel it touches
 * is painted from both coverages combined. */
static void stamp(ABBrushSurface *s,float cx,float cy,float size,float angle,float alpha,int second,const float *tint) {
    const uint8_t *tip=second?s->tip2:s->tip;
    int tip_w=second?s->tip2_w:s->tip_w, tip_h=second?s->tip2_h:s->tip_h;
    uint16_t **masks=second?s->mask2:s->mask;
    float scale=size/(float)(tip_w>tip_h?tip_w:tip_h);
    float extent=size*.7072f+1;
    int x0=(int)floorf(cx-extent), x1=(int)ceilf(cx+extent), y0=(int)floorf(cy-extent), y1=(int)ceilf(cy+extent);
    if(x0<0) x0=0;
    if(y0<0) y0=0;
    if(x1>s->width) x1=s->width;
    if(y1>s->height) y1=s->height;
    float ca=cosf(angle), sa=sinf(angle), depth=s->st[SP_GRAIN_DEPTH], gscale=s->st[SP_GRAIN_SCALE];
    uint32_t cap=(uint32_t)(s->opacity*ONE+.5f);
    uint32_t color[3]={(uint32_t)(s->rgb[0]*ONE+.5f),(uint32_t)(s->rgb[1]*ONE+.5f),(uint32_t)(s->rgb[2]*ONE+.5f)};
    for(int py=y0;py<y1;py++) for(int px=x0;px<x1;px++) {
        float dx=px+.5f-cx, dy=py+.5f-cy;
        float u=(dx*ca+dy*sa)/scale+tip_w*.5f-.5f, v=(-dx*sa+dy*ca)/scale+tip_h*.5f-.5f;
        if(u<-1||v<-1||u>tip_w||v>tip_h) continue;
        float c=sample(tip,tip_w,tip_h,u,v,0)*alpha;
        if(c<=1.0f/ONE) continue;
        int ti=(py/TILE)*s->columns+px/TILE, offset=((py%TILE)*TILE+px%TILE);
        if(!s->saved[ti]) {
            s->saved[ti]=1;
            if(s->tiles[ti]) {
                s->orig[ti]=malloc(CHANNELS*sizeof(uint16_t));
                if(!s->orig[ti]) { s->failed=1; return; }
                memcpy(s->orig[ti],s->tiles[ti],CHANNELS*sizeof(uint16_t));
            }
        }
        if(!masks[ti]) {
            masks[ti]=calloc(TILE*TILE,sizeof(uint16_t));
            if(!masks[ti]) { s->failed=1; return; }
        }
        uint32_t m=masks[ti][offset], d=(uint32_t)(c*ONE+.5f);
        if(d>ONE) d=ONE;
        m+=d*(ONE-m)/ONE;
        masks[ti][offset]=(uint16_t)m;
        if(s->wet&&!s->eraser) {
            /* The stroke's own paint: each dab's colour over what the stroke
             * laid before, capped and grained, then over the pixel as it was. */
            if(!s->paint[ti]) {
                s->paint[ti]=calloc(CHANNELS,sizeof(uint16_t));
                if(!s->paint[ti]) { s->failed=1; return; }
            }
            uint16_t *pp=s->paint[ti]+offset*4;
            if(!second) {
                uint32_t keep=ONE-d;
                for(int k=0;k<3;k++) pp[k]=(uint16_t)((uint32_t)(tint[k]*ONE+.5f)*d/ONE+pp[k]*keep/ONE);
                pp[3]=(uint16_t)(d+pp[3]*keep/ONE);
            }
            float pa=pp[3]*(1.0f/ONE), f=1;
            if(s->dual) {
                float a2=s->mask2[ti]?s->mask2[ti][offset]*(1.0f/ONE):0;
                f=pa>0?fminf(1,fmaxf(0,combine((int)s->dp[DP_MODE],pa,a2)))/pa:0;
            }
            float g=s->opacity*f;
            if(s->grain&&depth>0) g*=1-depth+depth*sample(s->grain,s->grain_w,s->grain_h,px/gscale,py/gscale,1);
            uint16_t *out=pixel(s,px,py,1);
            if(!out) return;
            s->dirty[ti]=1;
            const uint16_t *o=s->orig[ti]?s->orig[ti]+offset*4:NULL;
            uint32_t a=(uint32_t)(pp[3]*g+.5f);
            if(a>ONE) a=ONE;
            uint32_t keep=ONE-a;
            for(int k=0;k<4;k++) {
                uint32_t base=o?o[k]:0, paint=(uint32_t)(pp[k]*g+.5f);
                if(paint>ONE) paint=ONE;
                out[k]=(uint16_t)(paint+base*keep/ONE);
            }
            continue;
        }
        if(s->dual) {
            float a1=s->mask[ti]?s->mask[ti][offset]*(1.0f/ONE):0;
            float a2=s->mask2[ti]?s->mask2[ti][offset]*(1.0f/ONE):0;
            float k=combine((int)s->dp[DP_MODE],a1,a2);
            m=(uint32_t)(fminf(1,fmaxf(0,k))*ONE+.5f);
        }
        /* Grain textures the stroke's coverage, not each dab, so it shows
         * however much paint the dabs build up (Procreate's texturized grain). */
        uint32_t a=m*cap/ONE;
        if(s->grain&&depth>0)
            a=(uint32_t)(a*(1-depth+depth*sample(s->grain,s->grain_w,s->grain_h,px/gscale,py/gscale,1))+.5f);
        uint16_t *out=pixel(s,px,py,1);
        if(!out) return;
        s->dirty[ti]=1;
        const uint16_t *o=s->orig[ti]?s->orig[ti]+offset*4:NULL;
        uint32_t keep=ONE-a;
        for(int k=0;k<4;k++) {
            uint32_t base=o?o[k]:0, paint=s->eraser?0:(k<3?color[k]*a/ONE:a);
            out[k]=(uint16_t)(paint+base*keep/ONE);
        }
    }
}
static float dab_size(ABBrushSurface *s,float p) {
    float d=s->diameter*(1-s->st[SP_PRESSURE_SIZE]*(1-p));
    return d<.5f?.5f:d;
}
static void dab(ABBrushSurface *s,StampTrack *t,float x,float y,float p) {
    float size=dab_size(s,p)*(1-s->st[SP_SIZE_JITTER]*rnd(t));
    if(size<.5f) size=.5f;
    float scatter=s->st[SP_SCATTER]*size;
    if(scatter>0) { x+=(rnd(t)*2-1)*scatter; y+=(rnd(t)*2-1)*scatter; }
    float angle=s->st[SP_ROTATION]*AB_PI/180+(s->st[SP_FOLLOW]>.5f?t->direction:0)+
        s->st[SP_ROTATION_JITTER]*(rnd(t)*2-1)*AB_PI;
    float alpha=s->st[SP_FLOW]*(1-s->st[SP_PRESSURE_OPACITY]*(1-p))*(1-s->st[SP_OPACITY_JITTER]*rnd(t));
    /* Smudge strength is the opacity (with pressure), not the paint flow:
     * at low flow a drag would die out within a few pixels. */
    if(s->smudging) smudge_dab(s,t,x,y,size,angle,s->opacity*(1-s->st[SP_PRESSURE_OPACITY]*(1-p)));
    else if(alpha>0) {
        if(s->wet&&!s->eraser) {
            /* Pull: the brush takes up the colour under it (diluted paint
             * takes more), mixing it into what it carries. */
            float under[4];
            read_bilinear(s,x,y,under);
            float pull=fminf(1,s->wp[WP_PULL]+s->wp[WP_DILUTION]*.3f)*(under[3]/ONE);
            if(under[3]>0&&pull>0)
                for(int k=0;k<3;k++) t->res[k]+=(fminf(1,under[k]/under[3])-t->res[k])*pull;
            /* Charge: the paint runs out along the stroke; dilution thins it. */
            float charge=s->wp[WP_CHARGE];
            if(charge<1) alpha*=fmaxf(0,1-t->travel/(charge*30*s->diameter));
            alpha*=1-.75f*s->wp[WP_DILUTION];
            t->travel+=fmaxf(.5f,s->st[SP_SPACING]*size);
            if(alpha>0) stamp(s,x,y,size,angle,alpha,0,t->res);
        } else {
            stamp(s,x,y,size,angle,alpha,0,s->rgb);
        }
    }
}
/* A secondary dab: the primary's size (with pressure) times its own. */
static void dab2(ABBrushSurface *s,StampTrack *t,float x,float y,float p) {
    float size=dab_size(s,p)*s->dp[DP_SIZE]*(1-s->dp[DP_SIZE_JITTER]*rnd(t));
    if(size<.5f) size=.5f;
    float scatter=s->dp[DP_SCATTER]*size;
    if(scatter>0) { x+=(rnd(t)*2-1)*scatter; y+=(rnd(t)*2-1)*scatter; }
    float angle=(s->dp[DP_FOLLOW]>.5f?t->direction:0)+s->dp[DP_ROTATION_JITTER]*(rnd(t)*2-1)*AB_PI;
    stamp(s,x,y,size,angle,1,1,s->rgb);
}
static float spacing2(ABBrushSurface *s,float p) {
    return fmaxf(.5f,s->dp[DP_SPACING]*dab_size(s,p)*s->dp[DP_SIZE]);
}
static void stamp_point(ABBrushSurface *s,StampTrack *t,float x,float y,float p) {
    int dual=s->dual&&!s->smudging;
    if(!t->has_last) {
        t->has_last=1; t->last_x=x; t->last_y=y; t->last_p=p;
        t->remain=fmaxf(.5f,s->st[SP_SPACING]*dab_size(s,p));
        dab(s,t,x,y,p);
        if(dual) { t->remain2=spacing2(s,p); dab2(s,t,x,y,p); }
        return;
    }
    float dx=x-t->last_x, dy=y-t->last_y, dist=sqrtf(dx*dx+dy*dy);
    if(dist<1e-4f) { t->last_p=p; return; }
    t->direction=atan2f(dy,dx);
    float at=t->remain;
    while(at<=dist&&!s->failed) {
        float f=at/dist, pp=t->last_p+(p-t->last_p)*f;
        dab(s,t,t->last_x+dx*f,t->last_y+dy*f,pp);
        at+=fmaxf(.5f,s->st[SP_SPACING]*dab_size(s,pp));
    }
    t->remain=at-dist;
    if(dual) {
        float at2=t->remain2;
        while(at2<=dist&&!s->failed) {
            float f=at2/dist, pp=t->last_p+(p-t->last_p)*f;
            dab2(s,t,t->last_x+dx*f,t->last_y+dy*f,pp);
            at2+=spacing2(s,pp);
        }
        t->remain2=at2-dist;
    }
    t->last_x=x; t->last_y=y; t->last_p=p;
}
int ab_brush_smudge(ABBrushSurface *s,int on) {
    if(!s) return 0;
    s->smudging=on!=0;
    /* MyPaint smears with its own smudge: full pick-up, strength = opacity,
     * and a long memory so the colour travels with the stroke. */
    for(int i=0;i<AB_MAX_COPIES;i++) {
        mypaint_brush_set_base_value(s->brushes[i],MYPAINT_BRUSH_SETTING_SMUDGE,on?1.0f:s->preset_smudge);
        mypaint_brush_set_base_value(s->brushes[i],MYPAINT_BRUSH_SETTING_SMUDGE_LENGTH,on?0.95f:s->preset_smudge_length);
    }
    return 1;
}
int ab_symmetry(ABBrushSurface *s,const float *m,int count,float cx,float cy) {
    if(!s||!m||count<1||count>AB_MAX_COPIES||!isfinite(cx)||!isfinite(cy)) return 0;
    for(int i=0;i<count*4;i++) if(!isfinite(m[i])||fabsf(m[i])>1.0001f) return 0;
    for(int i=0;i<count;i++) memcpy(s->sym[i],m+i*4,4*sizeof(float));
    s->copies=count; s->sym_cx=cx; s->sym_cy=cy;
    return 1;
}
void ab_stroke_begin(ABBrushSurface *s) {
    if(!s) return;
    if(s->stamping) { stamp_begin(s); return; }
    for(int i=0;i<s->copies;i++) { mypaint_brush_reset(s->brushes[i]); mypaint_brush_new_stroke(s->brushes[i]); }
}
int ab_stroke_point(ABBrushSurface *s,float x,float y,float pressure,float xtilt,float ytilt,double seconds) {
    if(!s||s->failed||!isfinite(x)||!isfinite(y)||x< -4096||y< -4096||x>s->width+4096||y>s->height+4096||
       !isfinite(pressure)||pressure<0||pressure>1||!isfinite(xtilt)||fabsf(xtilt)>1||!isfinite(ytilt)||fabsf(ytilt)>1||
       !isfinite(seconds)||seconds<=0||seconds>1) return 0;
    if(s->stamping) {
        for(int i=0;i<s->copies&&!s->failed;i++) {
            const float *m=s->sym[i];
            float dx=x-s->sym_cx, dy=y-s->sym_cy;
            stamp_point(s,&s->tracks[i],s->sym_cx+m[0]*dx+m[1]*dy,s->sym_cy+m[2]*dx+m[3]*dy,pressure);
        }
        return !s->failed;
    }
    mypaint_tiled_surface_begin_atomic(&s->parent);
    for(int i=0;i<s->copies&&!s->failed;i++) {
        const float *m=s->sym[i];
        float dx=x-s->sym_cx, dy=y-s->sym_cy;
        float tx=m[0]*xtilt+m[1]*ytilt, ty=m[2]*xtilt+m[3]*ytilt;
        int result = mypaint_brush_stroke_to(s->brushes[i],(MyPaintSurface*)&s->parent,
            s->sym_cx+m[0]*dx+m[1]*dy,s->sym_cy+m[2]*dx+m[3]*dy,pressure,
            fmaxf(-1,fminf(1,tx)),fmaxf(-1,fminf(1,ty)),seconds);
        if (result < 0) s->failed = 1;
    }
    MyPaintRectangle rect;
    mypaint_tiled_surface_end_atomic(&s->parent,&rect);
    return !s->failed;
}
static uint16_t *pixel(ABBrushSurface *s,int x,int y,int allocate) {
    uint16_t **t=&s->tiles[(y/TILE)*s->columns+x/TILE];
    if(!*t&&allocate) { *t=calloc(CHANNELS,sizeof(uint16_t)); if(*t) s->allocated++; else s->failed=1; }
    return *t?*t+((y%TILE)*TILE+x%TILE)*4:NULL;
}
static int valid_rect(ABBrushSurface *s,int x,int y,int w,int h,size_t length) {
    return s&&x>=0&&y>=0&&w>0&&h>0&&x<=s->width-w&&y<=s->height-h&&length==(size_t)w*h*4;
}
int ab_surface_load_rgba_rect(ABBrushSurface *s,int x0,int y0,int w,int h,const uint8_t *rgba,size_t length) {
    if(!rgba||!valid_rect(s,x0,y0,w,h,length)) return 0;
    for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
        const uint8_t *in=rgba+((size_t)y*w+x)*4;
        uint16_t *out=pixel(s,x0+x,y0+y,in[3]!=0);
        if(!out) { if(s->failed) return 0; continue; }
        out[3]=((uint32_t)in[3]*ONE+127)/255;
        for(int c=0;c<3;c++) out[c]=((uint32_t)in[c]*out[3]+127)/255;
    }
    return 1;
}
int ab_surface_read_rgba_rect(ABBrushSurface *s,int x0,int y0,int w,int h,int premultiplied,uint8_t *rgba,size_t length) {
    if(!rgba||!valid_rect(s,x0,y0,w,h,length)||s->failed) return 0;
    for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
        uint8_t *out=rgba+((size_t)y*w+x)*4;
        uint16_t *in=pixel(s,x0+x,y0+y,0);
        if(!in||!in[3]) { memset(out,0,4); continue; }
        uint32_t a=in[3]>ONE?ONE:in[3];
        out[3]=(a*255+ONE/2)/ONE;
        for(int c=0;c<3;c++) {
            uint32_t v=premultiplied?((uint32_t)in[c]*255+ONE/2)/ONE:((uint32_t)in[c]*255+a/2)/a;
            uint32_t max=premultiplied?out[3]:255;
            out[c]=v>max?max:v;
        }
    }
    return 1;
}
int ab_surface_load_rgba(ABBrushSurface *s,const uint8_t *rgba,size_t length) {
    return s&&ab_surface_load_rgba_rect(s,0,0,s->width,s->height,rgba,length);
}
int ab_surface_read_rgba(ABBrushSurface *s,uint8_t *rgba,size_t length) {
    return s&&ab_surface_read_rgba_rect(s,0,0,s->width,s->height,0,rgba,length);
}
int ab_surface_take_dirty(ABBrushSurface *s,uint8_t *tiles,size_t length) {
    if(!s||!tiles||length!=(size_t)s->columns*s->rows) return -1;
    int count=0;
    for(size_t i=0;i<length;i++) { tiles[i]=s->dirty[i]; count+=s->dirty[i]; }
    memset(s->dirty,0,length);
    return count;
}
int ab_surface_allocated_tiles(ABBrushSurface *s) { return s?s->allocated:0; }
