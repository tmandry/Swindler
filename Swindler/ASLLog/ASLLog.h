#ifndef ASLLOG_H
#define ASLLOG_H

#import <Foundation/Foundation.h>
#import <asl.h>

/// Swift can't import C varargs methods that use ..., which asl_log does. This function wraps
/// asl_log so Swift can see it.
static void aslLog(const NSString *string, const int level) {
    asl_log(NULL, NULL, level, "%s", [string UTF8String]);
}

#endif  // ASLLOG_H
