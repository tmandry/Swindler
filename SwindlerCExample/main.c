//
//  main.c
//  SwindlerCExample
//
//  Created by Jeremy on 9/15/21.
//

#include <stdio.h>
#include <stdbool.h> // For bool type
#include <CoreFoundation/CoreFoundation.h> // For CFRunLoopRun
#include <CoreGraphics/CoreGraphics.h> // For CGRect
#include <Swindler-C.h>

int main(int argc, const char * argv[]) {
    SWStateRef s = SWStateInitialize();
    
    SWScreenRef mainScreen = SWStateGetMainScreen(s);
    CGRect screenFrame = SWScreenGetFrame(mainScreen);
    printf("Main screen frame: %.2f %.2f %.2f %.2f\n", screenFrame.origin.x, screenFrame.origin.y, screenFrame.size.width, screenFrame.size.height);
    
    uint32_t c = SWStateGetRunningApplications(s, NULL);
    SWApplicationRef apps[c];
    SWStateGetRunningApplications(s, apps);
    
    for (int i = 0; i < c; i++) {
        SWApplicationRef app = (apps[i]);
        printf("%d: %s\n", i, SWApplicationGetBundleIdentifier(app));
    }
    
    SWStateOnSpaceWillChange(s, ^(bool external, uint32_t *space_ids, int count) {
        printf("Space will change");
    });
    
    SWStateOnFrontmostApplicationDidChange(s, ^(bool external, SWApplicationRef from, SWApplicationRef to) {
        const char *to_bid = NULL;
        const char *from_bid = NULL;
        if (from) from_bid = SWApplicationGetBundleIdentifier(from);
        if (to) to_bid = SWApplicationGetBundleIdentifier(to);
        printf("Frontmost app changed from %s to %s\n", (from_bid ? from_bid : "unknown"), (to_bid ? to_bid : "unknown") );
    });
    
    SWStateOnWindowCreate(s, ^(bool external, SWWindowRef window) {
        printf("Window with title: %s was created\n", SWWindowGetTitle(window));
    });
    
    SWStateOnWindowDestroy(s, ^(bool external, SWWindowRef window) {
        printf("Window with title: %s was destroyed\n", SWWindowGetTitle(window));
    });
    
    SWStateOnApplicationDidLaunch(s, ^(bool external, SWApplicationRef app) {
        printf("Application with bundle id: %s was launched\n", SWApplicationGetBundleIdentifier(app));
    });
    
    SWStateOnWindowDidResize(s, ^(bool external, SWWindowRef window, CGRect from, CGRect to) {
        printf("Window resized from (%.2f, %.2f) to (%.2f, %.2f)\n", from.size.width, from.size.height, to.size.width, to.size.height);
    });
    
    SWStateOnWindowDidChangeTitle(s, ^(bool external, SWWindowRef window, const char *from, const char *to) {
        printf("Window changed title from %s to %s\n", from, to);
    });
    
    CFRunLoopRun();
    SwindlerDestroy(s);
    return 0;
}
