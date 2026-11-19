// 诊断版：确认 dylib 是否加载、hook 是否生效
// 往固定路径写标记文件，用它判断真实状态

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <stdio.h>

static const char *kMark = "/var/mobile/Library/Logs/dsh/cocoatopan-diag.txt";
static int gDrawCount = 0;
static int gHitCount = 0;

static void Mark(NSString *line) {
    FILE *f = fopen(kMark, "a");
    if (!f) return;
    fprintf(f, "%s\n", line.UTF8String);
    fclose(f);
}

static NSDictionary *gDict = nil;

static void LoadDict(void) {
    if (gDict) return;
    NSString *dir = [[NSBundle mainBundle] bundlePath];
    NSArray *cands = @[
        [dir stringByAppendingPathComponent:@"proc-cn.plist"],
        @"/var/jb/Library/Application Support/CocoaTopAN/proc-cn.plist",
    ];
    for (NSString *p in cands) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d.count) {
            gDict = d;
            Mark([NSString stringWithFormat:@"DICT OK %lu entries from %@", (unsigned long)d.count, p]);
            return;
        }
    }
    gDict = @{};
    Mark(@"DICT MISS");
}

// hook: -[NSString drawInRect:withAttributes:]
static void (*o1)(id, SEL, CGRect, NSDictionary *);
static void h1(id self, SEL _cmd, CGRect r, NSDictionary *a) {
    gDrawCount++;
    NSString *s = (NSString *)self;
    if (gDrawCount <= 5) {
        Mark([NSString stringWithFormat:@"drawInRect #%d: [%@]", gDrawCount, s]);
    }
    LoadDict();
    if (s.length > 1 && s.length < 40 && ![s containsString:@"/"] && ![s containsString:@" "] && ![s containsString:@" · "]) {
        NSString *cn = gDict[s];
        if (cn) {
            gHitCount++;
            if (gHitCount <= 5) Mark([NSString stringWithFormat:@"HIT: %@", s]);
            NSString *newS = [NSString stringWithFormat:@"%@ · %@", s, cn];
            NSMutableDictionary *a2 = [a mutableCopy];
            UIFont *f = a2[NSFontAttributeName];
            if (f) a2[NSFontAttributeName] = [f fontWithSize:f.pointSize * 0.7];
            [newS drawInRect:r withAttributes:a2];
            return;
        }
    }
    o1(self, _cmd, r, a);
}

// hook: -[NSAttributedString drawInRect:] （无属性参数版）
static void (*o2)(id, SEL, CGRect);
static void h2(id self, SEL _cmd, CGRect r) {
    gDrawCount++;
    NSAttributedString *as = (NSAttributedString *)self;
    NSString *s = as.string;
    if (gDrawCount <= 5) Mark([NSString stringWithFormat:@"attrDraw #%d: [%@]", gDrawCount, s]);
    LoadDict();
    if (s.length > 1 && s.length < 40 && ![s containsString:@"/"] && ![s containsString:@" "] && ![s containsString:@" · "]) {
        NSString *cn = gDict[s];
        if (cn) {
            gHitCount++;
            if (gHitCount <= 5) Mark([NSString stringWithFormat:@"HIT2: %@", s]);
            NSMutableAttributedString *m = [as mutableCopy];
            [m replaceCharactersInRange:NSMakeRange(0, m.length)
                             withString:[NSString stringWithFormat:@"%@ · %@", s, cn]];
            [m drawInRect:r];
            return;
        }
    }
    o2(self, _cmd, r);
}

__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        mkdir("/var/mobile/Library/Logs", 0755);
        mkdir("/var/mobile/Library/Logs/dsh", 0777);
        Mark(@"=== CocoaTopAN diag START ===");
        Mark([NSString stringWithFormat:@"bundle=%@", [[NSBundle mainBundle] bundlePath]]);
        LoadDict();

        Method m1 = class_getInstanceMethod([NSString class], @selector(drawInRect:withAttributes:));
        if (m1) {
            o1 = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)h1);
            Mark(@"hooked NSString drawInRect:withAttributes:");
        } else Mark(@"MISS drawInRect:withAttributes:");

        Method m2 = class_getInstanceMethod([NSAttributedString class], @selector(drawInRect:));
        if (m2) {
            o2 = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)h2);
            Mark(@"hooked NSAttributedString drawInRect:");
        } else Mark(@"MISS NSAttributedString drawInRect:");

        Mark(@"=== ready ===");
    }
}
