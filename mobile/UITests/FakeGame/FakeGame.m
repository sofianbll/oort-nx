// An invented game for the tests: the four entry points a game's framework has (App/ShellGlue.h) and one screen. No engine.
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include "ShellGlue.h"

int oort_invented_marker = 1;
const int dm_glue_version = DM_GLUE_VERSION;
static NSString *g_words;

static void leave(void) {
    void (*back)(void) = dlsym(RTLD_DEFAULT, "dm_shell_return_to_library");
    if (back) back();
}

const char *dm_glue_start_game(const char *const *argv, int argc, const void *image) {
    if (!image || argc < 3) return "The invented game got no arguments.";
    g_words = [NSString stringWithFormat:@"Invented game %s, save %s", argv[2], getenv("DM_SAVE") ? "ready" : "missing"];
    return NULL;
}

void dm_glue_present_game(void *window) {
    UIWindow *w = (__bridge UIWindow *)window;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.16 blue:0.3 alpha:1];
    UILabel *label = [UILabel new];
    label.text = g_words;
    label.textColor = UIColor.whiteColor;
    UIButton *quit = [UIButton buttonWithConfiguration:[UIButtonConfiguration filledButtonConfiguration] primaryAction:
        [UIAction actionWithTitle:@"Quit the invented game" image:nil identifier:nil handler:^(UIAction *a) { (void)a; leave(); }]];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, quit]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 24;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
                                              [stack.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor]]];
    w.rootViewController = vc;
}

void dm_glue_focus_event(int event) { if (event == DM_GLUE_FOCUS_REQUEST_QUIT) leave(); }
