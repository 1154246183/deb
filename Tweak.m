// CocoaTop 中文注解 —— CocoaTop 用 drawInRect:withAttributes: 直接绘制文本，
// 不走 UILabel，所以必须 hook NSString 的绘制方法。
// 适配：XinaA15 (rootful, /var/jb) / iOS 16 / arm64

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSDictionary<NSString *, NSString *> *gProcCN = nil;
static NSMutableSet<NSString *> *gSeen = nil;

static void LoadDict(void) {
    if (gProcCN != nil) return;
    NSString *bundleDir = [[NSBundle mainBundle] bundlePath];
    NSMutableArray *paths = [NSMutableArray array];
    if (bundleDir.length > 0) {
        [paths addObject:[bundleDir stringByAppendingPathComponent:@"proc-cn.plist"]];
        [paths addObject:[[bundleDir stringByDeletingLastPathComponent]
                          stringByAppendingPathComponent:@"proc-cn.plist"]];
    }
    [paths addObjectsFromArray:@[
        @"/var/jb/Library/Application Support/CocoaTopAN/proc-cn.plist",
        @"/Library/Application Support/CocoaTopAN/proc-cn.plist",
        @"/var/jb/usr/share/cocoatop-an/proc-cn.plist",
    ]];
    for (NSString *p in paths) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d.count > 0) {
            gProcCN = [d copy];
            NSLog(@"[CocoaTopAN] loaded %lu entries from %@", (unsigned long)d.count, p);
            return;
        }
    }
    gProcCN = @{};
    NSLog(@"[CocoaTopAN] dictionary NOT found");
}

static NSString *ProcKey(NSString *raw) {
    if (raw.length == 0) return nil;
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange r = [s rangeOfString:@" (" options:NSBackwardsSearch];
    if (r.location != NSNotFound && [s hasSuffix:@")"]) s = [s substringToIndex:r.location];
    if ([s containsString:@"/"]) s = [s lastPathComponent];
    return s;
}

// 只对「像进程名」的短字符串做替换：不含空格、不含路径、长度 2~40
static NSString *Annotate(NSString *original) {
    if (original.length < 2 || original.length > 40) return original;
    if ([original containsString:@" · "]) return original;
    if ([original containsString:@"/"]) return original;
    if ([original containsString:@" "]) return original;
    if ([original containsString:@"\n"]) return original;

    LoadDict();
    if (gProcCN.count == 0) return original;

    NSString *cn = gProcCN[original];
    if (cn.length == 0) return original;

    return [NSString stringWithFormat:@"%@ · %@", original, cn];
}

// 核心 hook：-[NSString drawInRect:withAttributes:]
static void (*orig_drawInRect)(id, SEL, CGRect, NSDictionary *);
static void hook_drawInRect(id self, SEL _cmd, CGRect rect, NSDictionary *attrs) {
    NSString *replaced = Annotate((NSString *)self);
    if (replaced != (NSString *)self) {
        // 缩小字号以容纳更长文本
        NSMutableDictionary *a2 = [attrs mutableCopy];
        UIFont *f = a2[NSFontAttributeName];
        if (f) a2[NSFontAttributeName] = [f fontWithSize:f.pointSize * 0.72];
        [(NSString *)replaced drawInRect:rect withAttributes:a2];
        return;
    }
    orig_drawInRect(self, _cmd, rect, attrs);
}

// 补充：-[NSString drawAtPoint:withAttributes:]
static void (*orig_drawAtPoint)(id, SEL, CGPoint, NSDictionary *);
static void hook_drawAtPoint(id self, SEL _cmd, CGPoint pt, NSDictionary *attrs) {
    NSString *replaced = Annotate((NSString *)self);
    if (replaced != (NSString *)self) {
        [(NSString *)replaced drawAtPoint:pt withAttributes:attrs];
        return;
    }
    orig_drawAtPoint(self, _cmd, pt, attrs);
}

// 补充：UILabel 路径（其它界面可能用）
static void (*orig_setText)(id, SEL, NSString *);
static void hook_setText(id self, SEL _cmd, NSString *text) {
    orig_setText(self, _cmd, Annotate(text));
}

static void Swap(Class cls, SEL sel, void *repl, void **orig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { NSLog(@"[CocoaTopAN] missing %@", NSStringFromSelector(sel)); return; }
    *orig = method_getImplementation(m);
    method_setImplementation(m, (IMP)repl);
    NSLog(@"[CocoaTopAN] hooked %@", NSStringFromSelector(sel));
}

__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        LoadDict();
        Swap([NSString class], @selector(drawInRect:withAttributes:),
             (void *)hook_drawInRect, (void **)&orig_drawInRect);
        Swap([NSString class], @selector(drawAtPoint:withAttributes:),
             (void *)hook_drawAtPoint, (void **)&orig_drawAtPoint);
        Swap([UILabel class], @selector(setText:),
             (void *)hook_setText, (void **)&orig_setText);
        NSLog(@"[CocoaTopAN] ready, %lu entries", (unsigned long)gProcCN.count);
    }
}
