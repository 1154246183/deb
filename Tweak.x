// CocoaTop 注解 —— 给进程列表加中文说明
// 编译：GitHub Actions（见 .github/workflows/build.yml）
// 安装：deb 包，注入 CocoaTop（ru.domo.cocoatop64）

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---------- 翻译表 ----------
static NSDictionary<NSString *, NSString *> *gProcCN = nil;

static void LoadDict(void) {
    if (gProcCN != nil) return;
    // 候选路径，按优先级
    NSArray *paths = @[
        @"/var/jb/Library/Application Support/CocoaTopAN/proc-cn.plist",
        @"/var/jb/usr/share/cocoatop-an/proc-cn.plist",
        @"/Library/Application Support/CocoaTopAN/proc-cn.plist",
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d.count > 0) {
            gProcCN = [d copy];
            NSLog(@"[CocoaTopAN] loaded %lu entries from %@", (unsigned long)d.count, p);
            return;
        }
    }
    gProcCN = @{};
    NSLog(@"[CocoaTopAN] no dictionary found, disabled");
}

// 提取进程名：可能是 "name" 或 "name (pid)" 或 裸路径
static NSString *ProcKey(NSString *raw) {
    if (raw.length == 0) return nil;
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // 去掉末尾的 " (1234)"
    NSRange r = [s rangeOfString:@" (" options:NSBackwardsSearch];
    if (r.location != NSNotFound && [s hasSuffix:@")"]) {
        s = [s substringToIndex:r.location];
    }
    // 若是路径，取末段
    if ([s containsString:@"/"]) {
        s = [s lastPathComponent];
    }
    return s;
}

// ---------- 核心：改写文本 ----------
static NSString *Annotate(NSString *original) {
    static NSString *marker = @" · ";
    if (original.length == 0) return original;
    if ([original containsString:marker]) return original;   // 已加过，别叠加

    LoadDict();
    if (gProcCN.count == 0) return original;

    NSString *key = ProcKey(original);
    if (key.length == 0) return original;

    NSString *cn = gProcCN[key];
    if (cn.length == 0) return original;

    // 保留原名的 pid 后缀（如果有）
    NSRange r = [original rangeOfString:@" (" options:NSBackwardsSearch];
    if (r.location != NSNotFound && [original hasSuffix:@")"]) {
        NSString *suffix = [original substringFromIndex:r.location];
        return [NSString stringWithFormat:@"%@%@%@%@", key, marker, cn, suffix];
    }
    return [NSString stringWithFormat:@"%@%@%@", original, marker, cn];
}

#pragma mark - Hook

// 1) UILabel.setText:
static void (*orig_setText)(id, SEL, NSString *);
static void hook_setText(id self, SEL _cmd, NSString *text) {
    orig_setText(self, _cmd, Annotate(text));
}

// 2) UITableViewCell.setTitle / 各种 setTitle:forState:
static void (*orig_setTitle)(id, SEL, NSString *);
static void hook_setTitle(id self, SEL _cmd, NSString *t) {
    orig_setTitle(self, _cmd, Annotate(t));
}

// 3) UIButton.setTitle:forState:
static void (*orig_setTitleState)(id, SEL, NSString *, UIControlState);
static void hook_setTitleState(id self, SEL _cmd, NSString *t, UIControlState st) {
    orig_setTitleState(self, _cmd, Annotate(t), st);
}

// 4) UILabel.setAttributedText: —— 有些列表用富文本
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
    if (!m) return;
    *orig = method_getImplementation(m);
    method_setImplementation(m, (IMP)repl);
}

__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        LoadDict();
        Swap([UILabel class], @selector(setText:), (void *)hook_setText, (void **)&orig_setText);
        Swap([UIButton class], @selector(setTitle:forState:), (void *)hook_setTitleState, (void **)&orig_setTitleState);
        NSLog(@"[CocoaTopAN] hooks installed, %lu entries", (unsigned long)gProcCN.count);
    }
}
