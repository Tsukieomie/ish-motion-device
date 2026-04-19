//
//  MotionDevice.m
//  iSH — Custom Hardware Patch
//
//  /dev/motion output format (one line per read, blocks until next update):
//
//    ax,ay,az,gx,gy,gz,pitch,roll,yaw,baro\n
//
//  Where:
//    ax/ay/az   = user acceleration (g-force, gravity removed), X/Y/Z
//    gx/gy/gz   = rotation rate (rad/s), X/Y/Z
//    pitch/roll/yaw = attitude in radians
//    baro       = relative altitude in meters (CMAltimeter, 0.0 if unavailable)
//
//  All values are signed doubles formatted to 6 decimal places.
//  Each read() blocks until the next CMDeviceMotion update (~60 Hz).
//
//  Drop-in companion to LocationDevice.m — registers as DYN_DEV_MAJOR, minor 2.
//

#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>
#include "kernel/fs.h"
#include "fs/dev.h"
#include "util/sync.h"

// ─── Motion tracker (singleton) ───────────────────────────────────────────────

@interface MotionTracker : NSObject

+ (MotionTracker *)instance;

@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) CMAltimeter *altimeter;
@property (nonatomic, strong) CMDeviceMotion *latestMotion;
@property (nonatomic) double latestRelativeAltitude; // metres
@property lock_t lock;
@property cond_t updateCond;

- (int)waitForUpdate;

@end

@implementation MotionTracker

+ (MotionTracker *)instance {
    static __weak MotionTracker *tracker;
    if (tracker == nil) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (tracker == nil) {
                tracker = [MotionTracker new];
            }
        });
        return tracker;
    }
    return tracker;
}

- (instancetype)init {
    if (self = [super init]) {
        lock_init(&_lock);
        cond_init(&_updateCond);

        self.motionManager = [CMMotionManager new];

        if (self.motionManager.isDeviceMotionAvailable) {
            self.motionManager.deviceMotionUpdateInterval = 1.0 / 60.0; // 60 Hz
            [self.motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue new]
                                                   withHandler:^(CMDeviceMotion *motion, NSError *error) {
                if (error) {
                    NSLog(@"MotionDevice: CMDeviceMotion error: %@", error);
                    return;
                }
                lock(&self->_lock);
                self.latestMotion = motion;
                notify(&self->_updateCond);
                unlock(&self->_lock);
            }];
        } else {
            NSLog(@"MotionDevice: CMDeviceMotion not available on this device");
        }

        // Barometer (relative altitude) — optional, gracefully absent
        if ([CMAltimeter isRelativeAltitudeAvailable]) {
            self.altimeter = [CMAltimeter new];
            [self.altimeter startRelativeAltitudeUpdatesToQueue:[NSOperationQueue new]
                                                   withHandler:^(CMAltitudeData *altData, NSError *error) {
                if (!error) {
                    lock(&self->_lock);
                    self.latestRelativeAltitude = altData.relativeAltitude.doubleValue;
                    unlock(&self->_lock);
                }
            }];
        }
    }
    return self;
}

- (int)waitForUpdate {
    lock(&_lock);
    CMDeviceMotion *old = self.latestMotion;
    int err = 0;
    while (self.latestMotion == old) {
        err = wait_for(&_updateCond, &_lock, NULL);
        if (err < 0) break;
    }
    unlock(&_lock);
    return err;
}

- (void)dealloc {
    [self.motionManager stopDeviceMotionUpdates];
    [self.altimeter stopRelativeAltitudeUpdates];
    cond_destroy(&_updateCond);
}

@end

// ─── Per-fd state ─────────────────────────────────────────────────────────────

@interface MotionFile : NSObject {
    NSData *buffer;
    size_t bufferOffset;
}

@property (nonatomic, strong) MotionTracker *tracker;

- (ssize_t)readIntoBuffer:(void *)buf size:(size_t)size;

@end

@implementation MotionFile

- (instancetype)init {
    if (self = [super init]) {
        self.tracker = [MotionTracker instance];
    }
    return self;
}

- (int)waitForUpdate {
    if (buffer != nil) return 0;

    int err = [self.tracker waitForUpdate];
    if (err < 0) return err;

    CMDeviceMotion *m = self.tracker.latestMotion;
    if (!m) return -EAGAIN;

    CMAcceleration a  = m.userAcceleration;
    CMRotationRate  g  = m.rotationRate;
    CMAttitude     *at = m.attitude;
    double baro        = self.tracker.latestRelativeAltitude;

    NSString *line = [NSString stringWithFormat:
        @"%+.6f,%+.6f,%+.6f,"   // ax, ay, az
         "%+.6f,%+.6f,%+.6f,"   // gx, gy, gz
         "%+.6f,%+.6f,%+.6f,"   // pitch, roll, yaw
         "%+.6f\n",              // baro
        a.x, a.y, a.z,
        g.x, g.y, g.z,
        at.pitch, at.roll, at.yaw,
        baro
    ];

    buffer       = [line dataUsingEncoding:NSUTF8StringEncoding];
    bufferOffset = 0;
    return 0;
}

- (ssize_t)readIntoBuffer:(void *)buf size:(size_t)size {
    @synchronized (self) {
        int err = [self waitForUpdate];
        if (err < 0) return err;

        size_t remaining = buffer.length - bufferOffset;
        if (size > remaining) size = remaining;
        [buffer getBytes:buf range:NSMakeRange(bufferOffset, size)];
        bufferOffset += size;
        if (bufferOffset == buffer.length) buffer = nil;
        return (ssize_t)size;
    }
}

@end

// ─── dev_ops implementation ───────────────────────────────────────────────────

static int motion_open(int major, int minor, struct fd *fd) {
    fd->data = (void *)CFBridgingRetain([MotionFile new]);
    return 0;
}

static int motion_close(struct fd *fd) {
    CFBridgingRelease(fd->data);
    return 0;
}

static ssize_t motion_read(struct fd *fd, void *buf, size_t size) {
    MotionFile *__bridge MotionFile *file = (__bridge MotionFile *)fd->data;
    return [file readIntoBuffer:buf size:size];
}

const struct dev_ops motion_dev = {
    .open    = motion_open,
    .fd.close = motion_close,
    .fd.read  = motion_read,
};
