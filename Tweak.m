// CocoaTop 中文注解 v2 —— 用 substrate 的 MSHookMessageEx（与原版汉化 dylib 同一条路）
// 诊断写到 App 自己的容器 Documents，避免沙盒阻挡
// 目标：XinaA15 rootful (/var/jb) / iOS 16 / arm64

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---- substrate ----
extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);

// ---- 诊断 ----
static char gDiag[512] = {0};
static int gDrawCount = 0;
static int gHitCount = 0;

static NSString *DiagPath(void) {
    // App 容器 Documents 一定可写
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = dirs.count ? dirs[0] : NSTemporaryDirectory();
    return [doc stringByAppendingPathComponent:@"cocoatopan-diag.txt"];
}

static void Mark(NSString *line) {
    NSString *p = DiagPath();
    FILE *f = fopen(p.UTF8String, "a");
    if (!f) return;
    fprintf(f, "%s\n", line.UTF8String);
    fclose(f);
}

// ---- 翻译表 ----
static NSDictionary *gDict = nil;

static void LoadDict(void) {
    if (gDict) return;
    NSString *dir = [[NSBundle mainBundle] bundlePath];
    NSArray *cands = @[
        [dir stringByAppendingPathComponent:@"proc-cn.plist"],
        @"/var/jb/Library/Application Support/CocoaTopAN/proc-cn.plist",
        @"/Library/Application Support/CocoaTopAN/proc-cn.plist",
    ];
    for (NSString *p in cands) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d.count) {
            gDict = d;
            Mark([NSString stringWithFormat:@"DICT OK %lu from %@", (unsigned long)d.count, p]);
            return;
        }
    }
    gDict = @{};
    Mark(@"DICT MISS");
}

static NSString *Annotate(NSString *s) {
    if (s.length < 2 || s.length > 40) return s;
    if ([s containsString:@"/"] || [s containsString:@" "] || [s containsString:@"\n"]) return s;
    if ([s containsString:@" · "]) return s;
    LoadDict();
    NSString *cn = gDict[s];
    if (!cn) return s;
    return [NSString stringWithFormat:@"%@ · %@", s, cn];
}

// ---- hook: UILabel setText: ----
static void (*orig_setText)(id, SEL, NSString *);
static void hook_setText(id self, SEL _cmd, NSString *text) {
    NSString *r = Annotate(text);
    if (r != text) {
        gHitCount++;
        if (gHitCount <= 8) Mark([NSString stringWithFormat:@"HIT setText: %@", text]);
    }
    orig_setText(self, _cmd, r);
}

// ---- hook: NSString drawInRect:withAttributes: ----
static void (*orig_drawAttr)(id, SEL, CGRect, NSDictionary *);
static void hook_drawAttr(id self, SEL _cmd, CGRect rect, NSDictionary *attrs) {
    gDrawCount++;
    NSString *s = (NSString *)self;
    if (gDrawCount <= 8) Mark([NSString stringWithFormat:@"draw#%d [%@]", gDrawCount, s]);
    NSString *r = Annotate(s);
    if (r != s) {
        gHitCount++;
        if (gHitCount <= 8) Mark([NSString stringWithFormat:@"HIT draw: %@", s]);
        NSMutableDictionary *a2 = [attrs mutableCopy];
        UIFont *f = a2[NSFontAttributeName];
        if (f) a2[NSFontAttributeName] = [f fontWithSize:f.pointSize * 0.7];
        [r drawInRect:rect withAttributes:a2];
        return;
    }
    orig_drawAttr(self, _cmd, rect, attrs);
}

__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        Mark(@"=== v2 START ===");
        Mark([NSString stringWithFormat:@"bundle=%@", [[NSBundle mainBundle] bundlePath]]);
        Mark([NSString stringWithFormat:@"diag=%@", DiagPath()]);

        LoadDict();

        MSHookMessageEx([UILabel class], @selector(setText:), (IMP)hook_setText, (IMP *)&orig_setText);
        Mark(@"hooked UILabel setText:");

        MSHookMessageEx([NSString class], @selector(drawInRect:withAttributes:),
                        (IMP)hook_drawAttr, (IMP *)&orig_drawAttr);
        Mark(@"hooked NSString drawInRect:withAttributes:");

        Mark(@"=== ready ===");
    }
}
