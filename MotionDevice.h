//
//  MotionDevice.h
//  iSH — Custom Hardware Patch
//
//  Adds /dev/motion: exposes CMMotionManager data (accelerometer,
//  gyroscope, attitude) as a readable character device.
//
//  Pattern modeled directly on LocationDevice.h
//

#pragma once
#include "fs/dev.h"

extern struct dev_ops motion_dev;
