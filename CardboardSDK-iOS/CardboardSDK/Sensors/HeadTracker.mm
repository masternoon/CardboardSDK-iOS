//
//  HeadTracker.mm
//  CardboardSDK-iOS
//
//  Created by Peter Tribe on 2014-08-25.
//  Copyright (c) 2014 Peter Tribe. All rights reserved.
//

#include "HeadTracker.h"

#define USE_EKF (1)

namespace {

GLKMatrix4 GetRotateEulerMatrix(float x, float y, float z)
{
    x *= (float)(M_PI / 180.0f);
    y *= (float)(M_PI / 180.0f);
    z *= (float)(M_PI / 180.0f);
    float cx = (float) cos(x);
    float sx = (float) sin(x);
    float cy = (float) cos(y);
    float sy = (float) sin(y);
    float cz = (float) cos(z);
    float sz = (float) sin(z);
    float cxsy = cx * sy;
    float sxsy = sx * sy;
    GLKMatrix4 matrix;
    matrix.m[0] = cy * cz;
    matrix.m[1] = -cy * sz;
    matrix.m[2] = sy;
    matrix.m[3] = 0.0f;
    matrix.m[4] = cxsy * cz + cx * sz;
    matrix.m[5] = -cxsy * sz + cx * cz;
    matrix.m[6] = -sx * cy;
    matrix.m[7] = 0.0f;
    matrix.m[8] = -sxsy * cz + sx * sz;
    matrix.m[9] = sxsy * sz + sx * cz;
    matrix.m[10] = cx * cy;
    matrix.m[11] = 0.0f;
    matrix.m[12] = 0.0f;
    matrix.m[13] = 0.0f;
    matrix.m[14] = 0.0f;
    matrix.m[15] = 1.0f;
    return matrix;
}

#if !USE_EKF
GLKMatrix4 GLMatrixFromRotationMatrix(CMRotationMatrix rotationMatrix)
{
    GLKMatrix4 glRotationMatrix;
    
    glRotationMatrix.m00 = rotationMatrix.m11;
    glRotationMatrix.m01 = rotationMatrix.m12;
    glRotationMatrix.m02 = rotationMatrix.m13;
    glRotationMatrix.m03 = 0.0f;
    
    glRotationMatrix.m10 = rotationMatrix.m21;
    glRotationMatrix.m11 = rotationMatrix.m22;
    glRotationMatrix.m12 = rotationMatrix.m23;
    glRotationMatrix.m13 = 0.0f;
    
    glRotationMatrix.m20 = rotationMatrix.m31;
    glRotationMatrix.m21 = rotationMatrix.m32;
    glRotationMatrix.m22 = rotationMatrix.m33;
    glRotationMatrix.m23 = 0.0f;

    glRotationMatrix.m30 = 0.0f;
    glRotationMatrix.m31 = 0.0f;
    glRotationMatrix.m32 = 0.0f;
    glRotationMatrix.m33 = 1.0f;

    return glRotationMatrix;
}
#endif
    
} // namespace

HeadTracker::HeadTracker() :
    // this assumes the device is landscape with the home button on the right
    _deviceToDisplay(GetRotateEulerMatrix(0.f, 0.f, -90.f)),
    // the inertial reference frame has z up and x forward, while the world has z out and x right
    _worldToInertialReferenceFrame(GetRotateEulerMatrix(-90.f, 0.f, 90.f)),
    _lastGyroEventTimestamp(0)
{
    _motionManager = [[CMMotionManager alloc] init];
    _tracker = new OrientationEKF();
}

HeadTracker::~HeadTracker()
{
    delete _tracker;
}

void HeadTracker::startTracking()
{
    _tracker->reset();

  #if USE_EKF
    NSOperationQueue *accelerometerQueue = [[NSOperationQueue alloc] init];
    NSOperationQueue *gyroQueue = [[NSOperationQueue alloc] init];
    
    // Probably capped at less than 100Hz
    // (http://stackoverflow.com/questions/4790111/what-is-the-official-iphone-4-maximum-gyroscope-data-update-frequency)
    _motionManager.accelerometerUpdateInterval = 1.0/100.0;
    [_motionManager startAccelerometerUpdatesToQueue:accelerometerQueue withHandler:^(CMAccelerometerData *accelerometerData, NSError *error)
    {
        CMAcceleration acceleration = accelerometerData.acceleration;
        // note core motion uses units of G while the EKF uses ms^-2
        const float kG = 9.81f;
        _tracker->processAcc(GLKVector3Make(kG*acceleration.x, kG*acceleration.y, kG*acceleration.z), accelerometerData.timestamp);
    }];
    
    _motionManager.gyroUpdateInterval = 1.0/100.0;
    [_motionManager startGyroUpdatesToQueue:gyroQueue withHandler:^(CMGyroData *gyroData, NSError *error) {
        CMRotationRate rotationRate = gyroData.rotationRate;
        _tracker->processGyro(GLKVector3Make(rotationRate.x, rotationRate.y, rotationRate.z), gyroData.timestamp);
        _lastGyroEventTimestamp = gyroData.timestamp;
    }];
  #else
    if (_motionManager.isDeviceMotionAvailable && !_motionManager.isDeviceMotionActive)
    {
        [_motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
    }
  #endif
    
}

void HeadTracker::stopTracking()
{
  #if USE_EKF
    [_motionManager stopAccelerometerUpdates];
    [_motionManager stopGyroUpdates];
  #else
    [_motionManager stopDeviceMotionUpdates];
  #endif
}

GLKMatrix4 HeadTracker::getLastHeadView()
{
  #if USE_EKF
    NSTimeInterval currentTimestamp = CACurrentMediaTime();
    double secondsSinceLastGyroEvent = currentTimestamp - _lastGyroEventTimestamp;
    // 1/30 of a second prediction (shoud it be 1/60?)
    double secondsToPredictForward = secondsSinceLastGyroEvent + 1.0/30;
    GLKMatrix4 inertialReferenceFrameToDevice = _tracker->getPredictedGLMatrix(secondsToPredictForward);
  #else
    CMDeviceMotion *motion = _motionManager.deviceMotion;
    CMRotationMatrix rotationMatrix = motion.attitude.rotationMatrix;
    GLKMatrix4 inertialReferenceFrameToDevice = GLKMatrix4Transpose(GLMatrixFromRotationMatrix(rotationMatrix)); // note the matrix inversion
  #endif
    
    GLKMatrix4 worldToDevice = GLKMatrix4Multiply(inertialReferenceFrameToDevice, _worldToInertialReferenceFrame);
    GLKMatrix4 worldToDisplay = GLKMatrix4Multiply(_deviceToDisplay, worldToDevice);
    
    // NSLog(@"%@", NSStringFromGLKMatrix4(worldToDisplay));
    
    return worldToDisplay;
}