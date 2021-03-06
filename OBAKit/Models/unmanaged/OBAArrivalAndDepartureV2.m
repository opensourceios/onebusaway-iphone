#import "OBAArrivalAndDepartureV2.h"
#import "OBADateHelpers.h"
#import "NSObject+OBADescription.h"

@interface OBAArrivalAndDepartureV2 ()
@property(nonatomic,strong) NSMutableArray *situationIds;
@end

@implementation OBAArrivalAndDepartureV2

- (instancetype)init {
    self = [super init];
    if (self) {
        _situationIds = [[NSMutableArray alloc] init];
    }
    return self;
}


- (OBARouteV2*) route {
    OBAReferencesV2 * refs = [self references];
    return [refs getRouteForId:self.routeId];
}

- (OBAStopV2*) stop {
    OBAReferencesV2 * refs = [self references];
    return [refs getStopForId:self.stopId];
}

- (OBATripV2*) trip {
    OBAReferencesV2 * refs = [self references];
    return [refs getTripForId:self.tripId];
}

- (NSString*)tripHeadsign {
    if (_tripHeadsign.length > 0) {
        return _tripHeadsign;
    }

    if (self.trip.tripHeadsign) {
        return self.trip.tripHeadsign;
    }

    if (self.trip.route.longName) {
        return self.trip.route.longName;
    }

    if (self.trip.route.shortName) {
        return self.trip.route.shortName;
    }

    return nil;
}

- (OBAArrivalAndDepartureInstanceRef *) instance {
    return [[OBAArrivalAndDepartureInstanceRef alloc] initWithTripInstance:self.tripInstance stopId:self.stopId stopSequence:self.stopSequence];
}

- (OBATripInstanceRef *) tripInstance {
    return [OBATripInstanceRef tripInstance:self.tripId serviceDate:self.serviceDate vehicleId:self.tripStatus.vehicleId];
}

- (long long) bestArrivalTime {
    return self.predictedArrivalTime == 0 ? self.scheduledArrivalTime : self.predictedArrivalTime;
}

- (long long) bestDepartureTime {
    return self.predictedDepartureTime == 0 ? self.scheduledDepartureTime : self.predictedDepartureTime;
}

- (BOOL)hasRealTimeData {
    return self.predictedDepartureTime > 0;
}

#pragma mark - OBAHasServiceAlerts

- (NSArray<OBASituationV2*>*)situations {

    NSMutableArray * rSituations = [NSMutableArray array];

    OBAReferencesV2 * refs = self.references;

    for( NSString * situationId in self.situationIds ) {
        OBASituationV2 * situation = [refs getSituationForId:situationId];
        if( situation )
            [rSituations addObject:situation];
    }

    return rSituations;
}

- (void) addSituationId:(NSString*)situationId {
    [self.situationIds addObject:situationId];
}

- (OBADepartureStatus)departureStatus {

    if (!self.hasRealTimeData) {
        return OBADepartureStatusUnknown;
    }

    double diff = (self.predictedDepartureTime - self.scheduledDepartureTime) / (1000.0 * 60.0);

    if (diff < -1.5) {
        return OBADepartureStatusEarly;
    }
    else if (diff < 1.5) {
        return OBADepartureStatusOnTime;
    }
    else {
        return OBADepartureStatusDelayed;
    }
}

- (NSString*)bestAvailableName {
    if (self.routeShortName) {
        return self.routeShortName;
    }

    OBATripV2* trip = self.trip;

    if (trip.routeShortName) {
        return trip.routeShortName;
    }

    return trip.route.shortName ?: trip.route.longName;
}

+ (NSString*)statusStringFromFrequency:(OBAFrequencyV2*)frequency {
    NSInteger headway = frequency.headway / 60;

    NSDate *now = [NSDate date];
    NSDate *startTime = [NSDate dateWithTimeIntervalSince1970:(frequency.startTime / 1000)];
    NSDate *endTime = [NSDate dateWithTimeIntervalSince1970:(frequency.endTime / 1000)];

    NSString *formatString = NSLocalizedString(@"Every %@ mins %@ %@", @"frequency status string");
    NSString *fromOrUntil = [now compare:startTime] == NSOrderedAscending ? NSLocalizedString(@"from", @"") : NSLocalizedString(@"until", @"");

    NSDate *terminalDate = [now compare:startTime] == NSOrderedAscending ? startTime : endTime;

    return [NSString stringWithFormat:formatString, @(headway), fromOrUntil, [OBADateHelpers formatShortTimeNoDate:terminalDate]];
}

- (double)predictedDepatureTimeDeviationFromScheduleInMinutes {

    if (self.departureStatus == OBADepartureStatusUnknown) {
        return NAN;
    }
    else {
        return (self.predictedDepartureTime - self.scheduledDepartureTime) / (1000.0 * 60.0);
    }
}

- (NSInteger)minutesUntilBestDeparture {
    NSDate *time = [NSDate dateWithTimeIntervalSince1970:(self.bestDepartureTime / 1000)];
    NSTimeInterval interval = [time timeIntervalSinceNow];
    return (NSInteger)(interval / 60.0);
}

- (NSString*)statusText {
    if (self.frequency) {
        return [OBAArrivalAndDepartureV2 statusStringFromFrequency:self.frequency];
    }

    OBADepartureStatus departureStatus = self.departureStatus;
    NSInteger minutes = [self minutesUntilBestDeparture];
    NSInteger minDiff = (NSInteger)fabs([self predictedDepatureTimeDeviationFromScheduleInMinutes]);

    if (departureStatus == OBADepartureStatusOnTime) {
        if (minutes < 0) {
            return NSLocalizedString(@"departed on time", @"minutes < 0");
        }
        else {
            return NSLocalizedString(@"on time", @"minutes >= 0");
        }
    }

    if (departureStatus == OBADepartureStatusUnknown) {
        if (minutes > 0) {
            return NSLocalizedString(@"scheduled arrival*", @"minutes >= 0");
        }
        else {
            return NSLocalizedString(@"scheduled departure*", @"minutes < 0");
        }
    }

    NSString *suffixWord = departureStatus == OBADepartureStatusEarly ? NSLocalizedString(@"early", @"") :
    NSLocalizedString(@"late", @"");

    if (minutes < 0) {
        return [NSString stringWithFormat:NSLocalizedString(@"departed %@ min %@", @"e.g. departed 5 min late"), @(minDiff), suffixWord];
    }
    else {
        return [NSString stringWithFormat:NSLocalizedString(@"%@ min %@", @"e.g. 3 min early"), @(minDiff), suffixWord];
    }
}

#pragma mark - NSObject

- (NSString*)description {
    return [self oba_description:@[@"routeId", @"route", @"routeShortName", @"tripId", @"trip", @"tripHeadsign", @"serviceDate", @"instance", @"tripInstance", @"stopId", @"stop", @"stopSequence", @"tripStatus", @"frequency", @"predicted", @"scheduledArrivalTime", @"predictedArrivalTime", @"bestArrivalTime", @"scheduledDepartureTime", @"predictedDepartureTime", @"bestDepartureTime", @"distanceFromStop", @"numberOfStopsAway"]];
}

@end