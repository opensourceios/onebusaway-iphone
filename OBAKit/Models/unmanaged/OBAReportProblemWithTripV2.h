#import "OBATripInstanceRef.h"
@import CoreLocation;

NS_ASSUME_NONNULL_BEGIN

@interface OBAReportProblemWithTripV2 : NSObject

@property (nonatomic,strong) OBATripInstanceRef *tripInstance;
@property (nonatomic,strong) NSString *stopId;
@property (nonatomic,strong) NSString *code;
@property (nonatomic,strong) NSString *userComment;
@property (nonatomic) BOOL userOnVehicle;
@property (nonatomic,strong) NSString *userVehicleNumber;
@property (nonatomic,strong) CLLocation *userLocation;

@end

NS_ASSUME_NONNULL_END