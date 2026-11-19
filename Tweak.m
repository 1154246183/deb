// CocoaTop 中文注解 —— 给进程列表加中文说明
// 适配：XinaA15 (rootless, /var/jb) / iOS 16 / arm64e
// 显示：进程名 · 中文说明

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSDictionary<NSString *, NSString *> *gProcCN = nil;

static void LoadDict(void) {
    if (gProcCN != nil) return;
    NSArray *paths = @[
        @"/var/jb/Library/Application Support/CocoaTopAN/proc-cn.plist",
        @"/var/jb/usr/share/cocoatop-an/proc-cn.plist",
        @"/Library/Application Support/CocoaTopAN/proc-cn.plist",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/proc-cn.plist",
    ];
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
    NSLog(@"[CocoaTopAN] dictionary not found");
}

static NSString *ProcKey(NSString *raw) {
    if (raw.length == 0) return nil;
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange r = [s rangeOfString:@" (" options:NSBackwardsSearch];
    if (r.location != NSNotFound && [s hasSuffix:@")"]) s = [s substringToIndex:r.location];
    if ([s containsString:@"/"]) s = [s lastPathComponent];
    return s;
}

static NSString *Annotate(NSString *original) {
    if (original.length == 0) return original;
    if ([original containsString:@" · "]) return original;

    LoadDict();
    if (gProcCN.count == 0) return original;

    NSString *key = ProcKey(original);
    if (key.length == 0) return original;

    NSString *cn = gProcCN[key];
    if (cn.length == 0) return original;

    NSRange r = [original rangeOfString:@" (" options:NSBackwardsSearch];
    if (r.location != NSNotFound && [original hasSuffix:@")"]) {
        return [NSString stringWithFormat:@"%@ · %@%@", key, cn, [original substringFromIndex:r.location]];
    }
    return [NSString stringWithFormat:@"%@ · %@", original, cn];
}

static void (*orig_setText)(id, SEL, NSString *);
static void hook_setText(id self, SEL _cmd, NSString *text) {
    orig_setText(self, _cmd, Annotate(text));
}

static void (*orig_setTitleState)(id, SEL, NSString *, UIControlState);
static void hook_setTitleState(id self, SEL _cmd, NSString *t, UIControlState st) {
    orig_setTitleState(self, _cmd, Annotate(t), st);
}

static void (*orig_setAttrText)(id, SEL, NSAttributedString *);
static void hook_setAttrText(id self, SEL _cmd, NSAttributedString *attr) {
    if (attr.length == 0) { orig_setAttrText(self, _cmd, attr); return; }
    NSString *plain = attr.string;
    NSString *done = Annotate(plain);
    if ([done isEqualToString:plain]) { orig_setAttrText(self, _cmd, attr); return; }
    NSMutableAttributedString *m = [attr mutableCopy];
    [m replaceCharactersInRange:NSMakeRange(0, m.length) withString:done];
    orig_setAttrText(self, _cmd, m);
}

static void Swap(Class cls, SEL sel, void *repl, void **orig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { NSLog(@"[CocoaTopAN] missing %@", NSStringFromSelector(sel)); return; }
    *orig = method_getImplementation(m);
    method_setImplementation(m, (IMP)repl);
}

__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        LoadDict();
        Swap([UILabel class], @selector(setText:), (void *)hook_setText, (void **)&orig_setText);
        Swap([UIButton class], @selector(setTitle:forState:), (void *)hook_setTitleState, (void **)&orig_setTitleState);
        Swap([UILabel class], @selector(setAttributedText:), (void *)hook_setAttrText, (void **)&orig_setAttrText);
        NSLog(@"[CocoaTopAN] ready, %lu entries", (unsigned long)gProcCN.count);
    }
}
