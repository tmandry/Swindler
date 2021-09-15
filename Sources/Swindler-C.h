//
//  Swindler-C.h
//  Swindler
//
//  Created by Jeremy on 9/15/21.
//

#ifndef Swindler_C_h
#define Swindler_C_h

#include <sys/types.h>

/// Forward declarations
typedef struct CGRect   CGRect;
typedef struct CGPoint  CGPoint;
typedef struct CGSize   CGSize;

/// Opaque structs for naming clarity
typedef struct SWState *         SWStateRef;
typedef struct SWScreen *        SWScreenRef;
typedef struct SWApplication *   SWApplicationRef;
typedef struct SWWindow *        SWWindowRef;
typedef struct SWSpace *         SWSpaceRef;

/// Callback function type for SWStateInitializeAsync
typedef void (*SWStateCreatedCallback)(SWStateRef _Nullable );

/// Empty block used for chaining operations
typedef void (^_Nullable SWCompletionBlock)(void);

#pragma mark    ---- State ----
/// Create an SWStateRef synchronously. Safe to call from main thread
SWStateRef _Nullable SWStateInitialize(void);

/// Promise-based creation
void SWStateInitializeAsync(SWStateCreatedCallback _Nonnull);

/// Not needed if you created stateRef in an autorelease pool
void SwindlerDestroy(SWStateRef _Nonnull stateRef);

uint32_t SWStateGetScreens(SWStateRef _Nonnull stateRef, SWScreenRef _Nullable * _Nullable screens);
uint32_t SWStateGetRunningApplications(SWStateRef _Nonnull stateRef, SWApplicationRef _Nullable * _Nullable apps);
uint32_t SWStateGetKnownWindows(SWStateRef _Nonnull stateRef, SWWindowRef _Nullable * _Nullable windows);
SWApplicationRef _Nullable SWStateGetFrontmostApplication(SWStateRef _Nonnull stateRef);
void SWStateSetFrontmostApplication(SWStateRef _Nonnull stateRef, SWApplicationRef _Nonnull appRef, SWCompletionBlock);


#pragma mark    ---- Screens ----
CGRect SWScreenGetFrame(SWScreenRef _Nonnull screenRef);
const char * _Nullable SWScreenGetDebugDescription(SWScreenRef _Nonnull screenRef);
int SWScreenGetSpaceID(SWScreenRef _Nonnull screenRef);


#pragma mark   ---- Applications ----
pid_t SWApplicationGetPid(SWApplicationRef _Nonnull appRef);
const char * _Nullable SWApplicationGetBundleIdentifier(SWApplicationRef _Nonnull appRef);
uint32_t SWStateGetKnownWindows(SWStateRef _Nonnull appRef, SWWindowRef _Nullable * _Nullable windows);
SWWindowRef _Nullable SWApplicationGetFocusedWindow(SWApplicationRef _Nonnull appRef);
SWWindowRef _Nullable SWApplicationGetMainWindow(SWApplicationRef _Nonnull appRef);
SWWindowRef _Nullable SWApplicationSetMainWindow(SWApplicationRef _Nonnull appRef, SWWindowRef _Nonnull windowRef, SWCompletionBlock);
_Bool SWApplicationGetIsHidden(SWApplicationRef _Nonnull appRef);
void SWApplicationSetIsHidden(SWApplicationRef _Nonnull, _Bool isHidden, SWCompletionBlock);


#pragma mark   ---- Windows ----
SWApplicationRef _Nullable SWWindowGetApplication(SWWindowRef _Nonnull winRef);
CGPoint SWWindowGetPosition(SWWindowRef _Nonnull winRef);
const char * _Nullable SWWindowGetTitle(SWWindowRef _Nonnull winRef);
SWScreenRef _Nullable SWWindowGetScreen(SWWindowRef _Nonnull winRef);

CGRect SWWindowGetFrame(SWWindowRef _Nonnull winRef);
void SWWindowSetFrame(SWWindowRef _Nonnull winRef, CGRect frame, SWCompletionBlock);

CGSize SWWindowGetSize(SWWindowRef _Nonnull winRef);
void SWWindowSetSize(SWWindowRef _Nonnull winRef, CGSize size, SWCompletionBlock);

_Bool SWWindowGetIsMinimized(SWWindowRef _Nonnull winRef);
void SWWindowSetIsMinimized(SWWindowRef _Nonnull winRef, _Bool isMinimized, SWCompletionBlock);

_Bool SWWindowGetIsFullscreen(SWWindowRef _Nonnull winRef);
void SWWindowSetIsFullscreen(SWWindowRef _Nonnull winRef, _Bool isFullscreen, SWCompletionBlock);


#pragma mark   ---- Events ----
/// Space events
void SWStateOnSpaceWillChange(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, uint32_t * _Nullable spaceIds, int count));
void SWStateOnSpaceDidChange(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, uint32_t * _Nullable spaceIds, int count));

/// Application events
void SWStateOnFrontmostApplicationDidChange(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWApplicationRef _Nullable from, SWApplicationRef _Nullable to));
void SWStateOnApplicationDidLaunch(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWApplicationRef _Nullable));
void SWStateOnApplicationDidTerminate(void * _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWApplicationRef _Nullable));
void SWStateOnApplicationIsHiddenDidChange(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWApplicationRef _Nullable, _Bool from, _Bool to));
void SWStateOnApplicationMainWindowDidChange(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWApplicationRef _Nullable, SWWindowRef _Nullable from, SWWindowRef _Nullable to));
void SWStateOnApplicationFocusWindowDidChange(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWApplicationRef _Nullable, SWWindowRef _Nullable from, SWWindowRef _Nullable to));

/// Window events
void SWStateOnWindowCreate(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWWindowRef _Nullable));
void SWStateOnWindowDestroy(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWWindowRef _Nullable));
void SWStateOnWindowDidResize(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWWindowRef _Nullable, CGRect from, CGRect to));
void SWStateOnWindowDidChangeTitle(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWWindowRef _Nullable, const char* _Nullable from, const char* _Nullable to));
void SWStateOnWindowMinimizeDidChange(SWStateRef _Nonnull stateRef, void (^ _Nonnull handler)(_Bool external, SWWindowRef _Nullable, _Bool from, _Bool to));


#endif /* Swindler_C_h */
