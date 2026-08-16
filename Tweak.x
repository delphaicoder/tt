/*
 * AppOpenAnimation — mo phong hieu ung mo/dong app kieu iOS 26 concept.
 *
 * ==== NGUON GOC THONG SO ====
 * Cac hang so ANIM_* ben duoi duoc tune dua tren PHAN TICH THUC TE video slow-motion
 * (khung hinh iOS 26 Beta, "Slowed to 20%"): do quy dao pixel qua tung frame, KHONG
 * phai doan chung chung. Ket qua: qua trinh mo KHONG co overshoot (khong nay/bounce
 * ro ret), damping cao, hoan tat hinh hoc trong ~100-110ms, hieu ung dong cham
 * hon mot chut (~130-150ms). Xem giai thich chi tiet trong tin nhan kem theo.
 *
 * ==== QUYET DINH KIEN TRUC AN TOAN (quan trong, doc truoc khi sua) ====
 * Tweak nay KHONG thay the pipeline mo app that cua SpringBoard (khong hook sau
 * vao SBUIAppOpenAnimationController). Ly do: do la be mat API rat de vo (private,
 * khong co class-dump de xac minh chinh xac tren iOS 15/16), neu hook sai co the
 * lam APP KHONG MO DUOC NUA hoac SpringBoard treo — rui ro qua cao de chay khong
 * test truoc tren thiet bi that.
 *
 * Thay vao do, dung ky thuat AN TOAN HON: bat cham vao icon (SBIconView), chup
 * nhanh (snapshot) hinh anh + vi tri icon, roi PHU MOT LOP OVERLAY RIENG chay
 * animation cua minh — trong khi %orig (con duong mo app that) VAN LUON DUOC GOI
 * KHONG DIEU KIEN. Neu overlay co loi, te nhat la animation khong dep — app van
 * luon mo duoc binh thuong. Day la nguyen tac an toan cot loi cua toan bo tweak.
 */

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - ==== CAC HANG SO CO THE TUY CHINH (tune tai day) ====

// Thoi gian animation hinh hoc luc DONG (full man hinh -> icon). Do thuc te: ~0.14s.
static const CFTimeInterval kCloseGeometryDuration = 0.14;

// Damping ratio cho UIViewPropertyAnimator (0.0 = nay vo han, 1.0 = khong nay chut nao).
// Du lieu do that tu Apple KHONG co overshoot (damping cao ~0.86) — nhung theo yeu
// cau, o day CHINH Y de co do nay ro rang hon (0.65-0.75 la khoang "nay vua", thap
// hon nua se nay nhieu lan truoc khi on dinh).
static const CGFloat kSpringDamping = 0.68;

// Van toc ban dau cua spring — mo phong "luc tha tay" luc cham. Tang nhe cung voi
// viec giam damping de cu "vot" dau ro hon, khop voi cam giac nay manh hon.
static const CGFloat kSpringInitialVelocity = 0.75;

// Thoi gian giu overlay (placeholder mo) truoc khi crossfade sang app that — du lieu
// do duoc cho thay co mot khoang tre ~100-130ms giua luc hinh hoc xong va luc UI that
// hien ra. Dat overlay tu bien mat sau khoang nay du app that co kip ve xong hay chua
// (an toan: khong bao gio giu overlay vo han).
static const CFTimeInterval kContentHoldDuration = 0.12;
static const CFTimeInterval kOverlayFadeOutDuration = 0.10;

// AN TOAN: thoi gian toi da overlay duoc phep ton tai truoc khi TU DONG bi xoa du
// bat ky chuyen gi xay ra — tranh truong hop overlay bi "ket" tren man hinh mai mai
// neu co loi logic nao do khong luong truoc duoc.
static const CFTimeInterval kOverlayHardTimeout = 1.2;

// ==== "The noi" (floating card) kieu iOS 26 concept trong anh tham khao ====
// Icon KHONG di thang tu nho -> full man hinh, ma dung lai giua chung o dang mot
// the noi bo tron, thay duoc wallpaper/dock xung quanh, roi moi mo tiep ra full.
// Ti le do tu anh: rong ~62% man hinh, canh tren ~13% chieu cao, cao ~58% chieu cao.
static const CGFloat kCardWidthRatio  = 0.62;
static const CGFloat kCardTopRatio    = 0.13;
static const CGFloat kCardHeightRatio = 0.58;
static const CGFloat kCardCornerRadius = 28.0; // bo goc lon, giu nguyen dang "the"
static const CFTimeInterval kCardStageDuration = 0.09; // thoi gian tu icon -> the
static const CFTimeInterval kCardHoldDuration  = 0.10; // dung lai o dang the bao lau
static const CFTimeInterval kCardToFullDuration = 0.10; // tu the -> full man hinh

// Mau overlay placeholder trong luc cho content that (do quan sat: khong phai den
// tuyet doi, ma la mau toi/xam nhat pha voi mau icon).
static UIColor *DI_PlaceholderColor(void) {
    return [UIColor colorWithWhite:0.08 alpha:0.92];
}

#pragma mark - AOOverlayView — lop rect chay animation (khong phai app that)

@interface AOOverlayView : UIView
@property (nonatomic, strong) UIImageView *snapshotView; // anh icon luc bat dau
@property (nonatomic, assign) BOOL isClosing;
@end

@implementation AOOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = DI_PlaceholderColor();
        self.layer.masksToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.userInteractionEnabled = NO; // KHONG BAO GIO chan tuong tac — chi de trang tri

        _snapshotView = [[UIImageView alloc] initWithFrame:self.bounds];
        _snapshotView.contentMode = UIViewContentModeScaleAspectFill;
        _snapshotView.clipsToBounds = YES;
        _snapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_snapshotView];
    }
    return self;
}

@end

#pragma mark - AOManager — dieu phoi animation, luu vi tri icon lan cuoi de dung khi dong

@interface AOManager : NSObject
@property (nonatomic, strong) AOOverlayView *activeOverlay;
@property (nonatomic, assign) CGRect lastIconFrameInScreen; // de dung lai khi app dong
@property (nonatomic, strong) UIImage *lastIconImage;
@property (nonatomic, assign) CGFloat lastIconCornerRadius;
@property (nonatomic, assign) BOOL appCurrentlyForeground;
+ (instancetype)sharedInstance;
- (void)playOpenAnimationFromIconView:(UIView *)iconView icon:(UIImage *)iconImage;
- (void)playCloseAnimation;
@end

@implementation AOManager

+ (instancetype)sharedInstance {
    static AOManager *inst = nil;
    if (!inst) {
        @synchronized ([AOManager class]) {
            if (!inst) inst = [AOManager new];
        }
    }
    return inst;
}

// Lay UIWindow tren cung hien co cua SpringBoard de gan overlay vao (khong tao window
// rieng lam gi cho phuc tap — overlay chi song trong vai tram ms roi tu xoa).
- (UIWindow *)topWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

#pragma mark Animation MO app

- (void)playOpenAnimationFromIconView:(UIView *)iconView icon:(UIImage *)iconImage {
    if (!iconView.window) return;
    UIWindow *host = [self topWindow];
    if (!host) return;

    CGRect startFrame = [iconView convertRect:iconView.bounds toView:host];
    CGRect fullFrame = host.bounds;

    // Rect "the noi" giua chung — chinh giua ngang, dua theo ti le do tu anh tham khao.
    CGFloat cardW = fullFrame.size.width * kCardWidthRatio;
    CGFloat cardH = fullFrame.size.height * kCardHeightRatio;
    CGRect cardFrame = CGRectMake((fullFrame.size.width - cardW) / 2.0,
                                   fullFrame.size.height * kCardTopRatio,
                                   cardW, cardH);

    // Luu lai de dung khi dong app (animation dong se thu ve DUNG vi tri icon nay).
    self.lastIconFrameInScreen = startFrame;
    self.lastIconImage = iconImage;
    self.lastIconCornerRadius = iconView.layer.cornerRadius;

    [self.activeOverlay removeFromSuperview]; // don overlay cu neu lo con sot (an toan)

    AOOverlayView *overlay = [[AOOverlayView alloc] initWithFrame:startFrame];
    overlay.snapshotView.image = iconImage;
    overlay.layer.cornerRadius = iconView.layer.cornerRadius;
    overlay.alpha = 1.0;
    [host addSubview:overlay];
    self.activeOverlay = overlay;

    // ==== Giai doan 1: icon -> the noi (co nay) ====
    UISpringTimingParameters *timing1 = [[UISpringTimingParameters alloc]
        initWithDampingRatio:kSpringDamping
        initialVelocity:CGVectorMake(kSpringInitialVelocity, kSpringInitialVelocity)];
    UIViewPropertyAnimator *stage1 = [[UIViewPropertyAnimator alloc]
        initWithDuration:kCardStageDuration timingParameters:timing1];
    [stage1 addAnimations:^{
        overlay.frame = cardFrame;
        overlay.layer.cornerRadius = kCardCornerRadius;
        overlay.snapshotView.alpha = 0.35;
    }];

    __weak AOOverlayView *weakOverlay = overlay;
    __weak AOManager *weakSelf = self;
    [stage1 addCompletion:^(UIViewAnimatingPosition finalPosition) {
        AOOverlayView *ov = weakOverlay;
        AOManager *strongSelf = weakSelf;
        if (!ov || !strongSelf) return;

        // ==== Dung lai o dang "the noi" trong kCardHoldDuration (dung nhu anh) ====
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCardHoldDuration * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (!ov.superview) return; // co the da bi xoa boi hard timeout, kiem tra an toan

                // ==== Giai doan 2: the noi -> full man hinh, roi lo app that ====
                UIViewPropertyAnimator *stage2 = [[UIViewPropertyAnimator alloc]
                    initWithDuration:kCardToFullDuration dampingRatio:0.92 // giai doan nay giu em diu, khong nay nua
                    animations:^{
                        ov.frame = fullFrame;
                        ov.layer.cornerRadius = 0;
                    }];
                [stage2 addCompletion:^(UIViewAnimatingPosition finalPosition2) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kContentHoldDuration * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                            [UIView animateWithDuration:kOverlayFadeOutDuration animations:^{
                                ov.alpha = 0;
                            } completion:^(BOOL finished) {
                                [ov removeFromSuperview];
                            }];
                        });
                }];
                [stage2 startAnimation];
            });
    }];
    [stage1 startAnimation];

    // AN TOAN: bat buoc xoa overlay sau kOverlayHardTimeout du bat ky chuyen gi xay ra
    // (ke ca neu ca 2 giai doan tren vi ly do nao do khong hoan tat).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOverlayHardTimeout * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [overlay removeFromSuperview];
        });
}

#pragma mark Animation DONG app (thu ve dung vi tri icon da luu luc mo)

- (void)playCloseAnimation {
    if (CGRectIsEmpty(self.lastIconFrameInScreen)) return; // chua tung mo qua icon nao, bo qua an toan
    UIWindow *host = [self topWindow];
    if (!host) return;

    [self.activeOverlay removeFromSuperview];

    CGRect fullFrame = host.bounds;
    CGFloat cardW = fullFrame.size.width * kCardWidthRatio;
    CGFloat cardH = fullFrame.size.height * kCardHeightRatio;
    CGRect cardFrame = CGRectMake((fullFrame.size.width - cardW) / 2.0,
                                   fullFrame.size.height * kCardTopRatio,
                                   cardW, cardH);

    AOOverlayView *overlay = [[AOOverlayView alloc] initWithFrame:fullFrame];
    overlay.snapshotView.image = self.lastIconImage;
    overlay.snapshotView.alpha = 0;
    overlay.layer.cornerRadius = 0;
    [host addSubview:overlay];
    self.activeOverlay = overlay;

    CGRect target = self.lastIconFrameInScreen;
    CGFloat targetCorner = self.lastIconCornerRadius;

    // ==== Giai doan 1: full man hinh -> the noi (doi xung voi luc mo) ====
    UIViewPropertyAnimator *stage1 = [[UIViewPropertyAnimator alloc]
        initWithDuration:kCardToFullDuration dampingRatio:0.92
        animations:^{
            overlay.frame = cardFrame;
            overlay.layer.cornerRadius = kCardCornerRadius;
        }];

    __weak AOOverlayView *weakOverlayClose = overlay;
    [stage1 addCompletion:^(UIViewAnimatingPosition finalPosition) {
        AOOverlayView *ov = weakOverlayClose;
        if (!ov) return;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCardHoldDuration * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (!ov.superview) return;

                // ==== Giai doan 2: the noi -> icon (co nay) ====
                UIViewPropertyAnimator *stage2 = [[UIViewPropertyAnimator alloc]
                    initWithDuration:kCloseGeometryDuration
                    dampingRatio:kSpringDamping
                    animations:^{
                        ov.frame = target;
                        ov.layer.cornerRadius = targetCorner;
                        ov.snapshotView.alpha = 1.0;
                    }];
                [UIView animateWithDuration:kOverlayFadeOutDuration
                                       delay:MAX(0, kCloseGeometryDuration - kOverlayFadeOutDuration)
                                     options:UIViewAnimationOptionCurveEaseOut
                                  animations:^{ ov.alpha = 0; }
                                  completion:nil];
                [stage2 addCompletion:^(UIViewAnimatingPosition finalPosition2) {
                    [ov removeFromSuperview];
                }];
                [stage2 startAnimation];
            });
    }];
    [stage1 startAnimation];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOverlayHardTimeout * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [overlay removeFromSuperview]; }); // an toan, nhu tren
}

@end

#pragma mark - Hook diem kich hoat: cham icon (MO) va quay lai SpringBoard (DONG)

// SBIconView khong co header chinh thuc — khai bao toi thieu de bien dich duoc.
// KHONG can biet chinh xac toan bo giao dien cua no vi chi dung 2 phuong thuc
// UIResponder tieu chuan (touchesBegan/touchesEnded) ma MOI UIView deu co san.
@interface SBIconView : UIView
@end

// Luu tam anh icon + view luc bat dau cham, dung associated object (an toan, khong
// can sua @interface goc).
static const void *kIconSnapshotKey = &kIconSnapshotKey;

%hook SBIconView

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig; // LUON goi truoc — dam bao hanh vi goc khong bao gio bi anh huong

    UIView *v = (UIView *)self;
    // Chup nhanh hinh anh icon NGAY LUC BAT DAU CHAM (khi con nguyen, chua bi
    // SpringBoard tu lam mo/an di trong luc xu ly cham).
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:v.bounds.size format:fmt];
    UIImage *snap = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [v drawViewHierarchyInRect:v.bounds afterScreenUpdates:NO];
    }];
    objc_setAssociatedObject(v, kIconSnapshotKey, snap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    // QUAN TRONG: goi %orig TRUOC TIEN, KHONG DIEU KIEN — day la con duong mo app
    // THAT cua he thong, tuyet doi khong duoc chan/tri hoan no vi bat ky ly do gi.
    %orig;

    UIView *v = (UIView *)self;
    UIImage *snap = objc_getAssociatedObject(v, kIconSnapshotKey);
    if (!snap) return; // khong co snapshot (vd cham bi huy giua chung) -> bo qua an toan

    // Phat animation overlay CUA RIENG MINH — hoan toan doc lap voi viec app that
    // co mo hay khong (da duoc %orig xu ly xong o tren roi).
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AOManager sharedInstance] playOpenAnimationFromIconView:v icon:snap];
    });
}

%end

// Kich hoat animation DONG khi SpringBoard tro lai foreground (nghia la vua roi
// khoi 1 app nao do). Day la notification CONG KHAI, an toan, khong phai private API.
%hook SpringBoard
- (void)applicationDidBecomeActive:(id)application {
    %orig;
    if ([AOManager sharedInstance].appCurrentlyForeground) {
        [AOManager sharedInstance].appCurrentlyForeground = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AOManager sharedInstance] playCloseAnimation];
        });
    }
}
- (void)applicationDidResignActive:(id)application {
    %orig;
    // SpringBoard vua nhuong foreground cho 1 app khac -> danh dau de lan sau quay
    // lai (applicationDidBecomeActive ben tren) biet la dang "dong app tro ve".
    [AOManager sharedInstance].appCurrentlyForeground = YES;
}
%end

%ctor {
    // Khong lam gi dac biet luc khoi dong — moi thu deu duoc kich hoat qua cac hook
    // o tren, khong can thiet lap gi truoc.
}
