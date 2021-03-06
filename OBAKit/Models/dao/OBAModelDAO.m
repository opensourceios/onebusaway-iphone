/**
 * Copyright (C) 2009 bdferris <bdferris@onebusaway.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *         http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "OBAModelDAO.h"
#import "OBALogger.h"
#import "OBACommon.h"
#import "OBACommonV1.h"
#import "OBAMacros.h"
#import "OBAStopAccessEventV2.h"
#import "OBASituationV2.h"
#import "OBAModelDAOUserPreferencesImpl.h"
#import "OBAPlacemark.h"
#import "OBABookmarkGroup.h"

const NSInteger kMaxEntriesInMostRecentList = 10;

@interface OBAModelDAO ()
@property(nonatomic,strong) id<OBAModelPersistenceLayer> preferencesDao;
@end

@implementation OBAModelDAO {
    NSMutableArray * _bookmarks;
    NSMutableArray * _bookmarkGroups;
    NSMutableArray * _mostRecentStops;
    NSMutableDictionary * _stopPreferences;
    CLLocation * _mostRecentLocation;
    NSMutableSet * _visitedSituationIds;
    NSMutableArray * _mostRecentCustomApiUrls;
}
@dynamic hideFutureLocationWarnings;

- (instancetype)initWithModelPersistenceLayer:(id<OBAModelPersistenceLayer>)persistenceLayer {
    self = [super init];

    if (self) {
        _preferencesDao = persistenceLayer;
        _bookmarks = [[NSMutableArray alloc] initWithArray:[_preferencesDao readBookmarks]];
        _bookmarkGroups = [[NSMutableArray alloc] initWithArray:[_preferencesDao readBookmarkGroups]];
        _mostRecentStops = [[NSMutableArray alloc] initWithArray:[_preferencesDao readMostRecentStops]];
        _stopPreferences = [[NSMutableDictionary alloc] initWithDictionary:[_preferencesDao readStopPreferences]];
        _mostRecentLocation = [_preferencesDao readMostRecentLocation];
        _visitedSituationIds = [[NSMutableSet alloc] initWithSet:[_preferencesDao readVisistedSituationIds]];
        _region = [_preferencesDao readOBARegion];
        _mostRecentCustomApiUrls = [[NSMutableArray alloc] initWithArray:[_preferencesDao readMostRecentCustomApiUrls]];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(viewedArrivalsAndDeparturesForStop:) name:OBAViewedArrivalsAndDeparturesForStopNotification object:nil];
    }

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OBAViewedArrivalsAndDeparturesForStopNotification object:nil];
}

#pragma mark - Recent

- (NSArray*) mostRecentStops {
    return _mostRecentStops;
}

- (NSArray*) mostRecentCustomApiUrls {
    return _mostRecentCustomApiUrls;
}

- (CLLocation*) mostRecentLocation {
    return _mostRecentLocation;
}

- (void) setMostRecentLocation:(CLLocation*)location {
    _mostRecentLocation = location;
    [_preferencesDao writeMostRecentLocation:location];
}

#pragma mark - Regions

- (void)setRegion:(OBARegionV2 *)region {
    if (_region == region) {
        return;
    }

    _region = region;
    [_preferencesDao writeOBARegion:region];
}

- (BOOL) readSetRegionAutomatically {
    return [_preferencesDao readSetRegionAutomatically];
}

- (void) writeSetRegionAutomatically:(BOOL)setRegionAutomatically {
    [_preferencesDao writeSetRegionAutomatically:setRegionAutomatically];
}

#pragma mark - Bookmarks

- (OBABookmarkV2*)bookmarkForStop:(OBAStopV2*)stop {
    for (OBABookmarkV2 *bm in self.ungroupedBookmarks) {
        if ([bm.stopId isEqual:stop.stopId]) {
            return bm;
        }
    }

    for (OBABookmarkGroup *group in self.bookmarkGroups) {
        for (OBABookmarkV2 *bm in group.bookmarks) {
            if ([bm.stopId isEqual:stop.stopId]) {
                return bm;
            }
        }
    }

    return nil;
}

- (NSArray*)ungroupedBookmarks {
    return _bookmarks;
}

- (NSArray*)allBookmarks {
    NSMutableArray *all = [[NSMutableArray alloc] initWithArray:self.ungroupedBookmarks];
    for (OBABookmarkGroup *group in self.bookmarkGroups) {
        [all addObjectsFromArray:group.bookmarks];
    }
    return [NSArray arrayWithArray:all];
}

- (NSArray*)bookmarksForCurrentRegion {
    if (self.region) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K IN %@", NSStringFromSelector(@selector(regionIdentifier)), @[@(self.region.identifier)]];

        return [self.allBookmarks filteredArrayUsingPredicate:predicate];
    }
    else {
        return @[];
    }
}

- (NSArray *)bookmarkGroups {
    return _bookmarkGroups;
}

- (void)saveBookmark:(OBABookmarkV2*)bookmark {
    if (bookmark.group) {
        [self saveBookmarkGroup:bookmark.group];
    }
    else {
        if (![_bookmarks containsObject:bookmark]) {
            [_bookmarks addObject:bookmark];
        }

        [_preferencesDao writeBookmarks:_bookmarks];
    }
}

- (void)moveBookmark:(NSUInteger)startIndex to:(NSUInteger)endIndex {
    if (startIndex == endIndex) {
        return;
    }

    if (startIndex >= _bookmarks.count) {
        return;
    }

    @synchronized (self) {
        NSUInteger bookmarksCount = _bookmarks.count;

        OBABookmarkV2 * bm = _bookmarks[startIndex];
        [_bookmarks removeObjectAtIndex:startIndex];

        // If the caller put this bookmark out of bounds, then
        // just stick the bookmark at the end of the array and
        // call it a day.
        endIndex = MIN(endIndex, bookmarksCount - 1);
        [_bookmarks insertObject:bm atIndex:endIndex];
        [_preferencesDao writeBookmarks:_bookmarks];
    }
}

- (void)removeBookmark:(OBABookmarkV2*)bookmark {
    if (bookmark.group) {
        OBABookmarkGroup *group = bookmark.group;

        [group.bookmarks removeObject:bookmark];

        // The group is empty. Delete it.
        if (group.bookmarks.count == 0) {
            [_bookmarkGroups removeObject:group];
        }

        [_preferencesDao writeBookmarkGroups:_bookmarkGroups];
    }
    else {
        [_bookmarks removeObject:bookmark];
        [_preferencesDao writeBookmarks:_bookmarks];
    }
}

- (void)saveBookmarkGroup:(OBABookmarkGroup *)bookmarkGroup {
    if (![_bookmarkGroups containsObject:bookmarkGroup]) {
        [_bookmarkGroups addObject:bookmarkGroup];
    }
    [_bookmarkGroups sortUsingComparator:^NSComparisonResult(OBABookmarkGroup *obj1, OBABookmarkGroup *obj2) {
        return [obj1.name compare:obj2.name];
    }];
    [_preferencesDao writeBookmarkGroups:_bookmarkGroups];
}

- (void)removeBookmarkGroup:(OBABookmarkGroup *)bookmarkGroup {
    for (OBABookmarkV2 *bm in bookmarkGroup.bookmarks) {
        [_bookmarks addObject:bm];
        bm.group = nil;
    }
    [_bookmarkGroups removeObject:bookmarkGroup];
    [_preferencesDao writeBookmarks:_bookmarks];
    [_preferencesDao writeBookmarkGroups:_bookmarkGroups];
}

- (void)moveBookmark:(OBABookmarkV2*)bookmark toGroup:(OBABookmarkGroup*)group {
    if (!group) {
        [_bookmarks addObject:bookmark];
        [bookmark.group.bookmarks removeObject:bookmark];
    }
    else if (bookmark.group) {
        [bookmark.group.bookmarks removeObject:bookmark];
        [group.bookmarks addObject:bookmark];
    }
    else {
        [_bookmarks removeObject:bookmark];
        [group.bookmarks addObject:bookmark];
    }
    bookmark.group = group;
    [_preferencesDao writeBookmarks:_bookmarks];
    [_preferencesDao writeBookmarkGroups:_bookmarkGroups];
}

- (void)moveBookmark:(NSUInteger)startIndex to:(NSUInteger)endIndex inGroup:(OBABookmarkGroup*)group {
    if (startIndex == endIndex) {
        return;
    }

    NSUInteger bookmarksCount = group.bookmarks.count;

    if (startIndex >= bookmarksCount) {
        return;
    }

    @synchronized (self) {
        OBABookmarkV2 *bm = group.bookmarks[startIndex];
        [group.bookmarks removeObjectAtIndex:startIndex];

        // If the caller put this bookmark out of bounds, then
        // just stick the bookmark at the end of the array and
        // call it a day.
        [group.bookmarks insertObject:bm atIndex:MIN(endIndex, bookmarksCount - 1)];
        [_preferencesDao writeBookmarkGroups:_bookmarkGroups];
    }
}

#pragma mark - Stop Preferences

- (OBAStopPreferencesV2*) stopPreferencesForStopWithId:(NSString*)stopId {
    OBAStopPreferencesV2 * prefs = _stopPreferences[stopId];
    if( ! prefs )
        return [[OBAStopPreferencesV2 alloc] init];
    return [[OBAStopPreferencesV2 alloc] initWithStopPreferences:prefs];
}

- (void) setStopPreferences:(OBAStopPreferencesV2*)preferences forStopWithId:(NSString*)stopId {
    _stopPreferences[stopId] = preferences;
    [_preferencesDao writeStopPreferences:_stopPreferences];
}

#pragma mark - Location Warnings

- (BOOL) hideFutureLocationWarnings {
    return [_preferencesDao hideFutureLocationWarnings];
}

- (void) setHideFutureLocationWarnings:(BOOL)hideFutureLocationWarnings {
    [_preferencesDao setHideFutureLocationWarnings:hideFutureLocationWarnings];
}

#pragma mark - Stop Viewing

- (void) addStopAccessEvent:(OBAStopAccessEventV2*)event {

    OBAStopAccessEventV2 * existingEvent = nil;

    NSArray * stopIds = event.stopIds;

    for( OBAStopAccessEventV2 * stopEvent in _mostRecentStops ) {
        if( [stopEvent.stopIds isEqual:stopIds] ) {
            existingEvent = stopEvent;
            break;
        }
    }

    if( existingEvent ) {
        [_mostRecentStops removeObject:existingEvent];
        [_mostRecentStops insertObject:existingEvent atIndex:0];
    }
    else {
        existingEvent = [[OBAStopAccessEventV2 alloc] init];
        existingEvent.stopIds = stopIds;
        [_mostRecentStops insertObject:existingEvent atIndex:0];
    }

    existingEvent.title = event.title;
    existingEvent.subtitle = event.subtitle;

    NSInteger over = [_mostRecentStops count] - kMaxEntriesInMostRecentList;
    for( int i=0; i<over; i++)
        [_mostRecentStops removeObjectAtIndex:([_mostRecentStops count]-1)];

    [_preferencesDao writeMostRecentStops:_mostRecentStops];
    [[NSNotificationCenter defaultCenter] postNotificationName:OBAMostRecentStopsChangedNotification object:nil];
}

- (void)viewedArrivalsAndDeparturesForStop:(NSNotification*)note {
    OBAStopV2* stop = [note object];
    OBAStopAccessEventV2 * event = [[OBAStopAccessEventV2 alloc] init];
    event.stopIds = @[stop.stopId];
    event.title = stop.title;
    event.subtitle = stop.subtitle;
    [self addStopAccessEvent:event];
}

- (BOOL)isVisitedSituationWithId:(NSString*)situationId {
    return [_visitedSituationIds containsObject:situationId];
}

- (OBAServiceAlertsModel*)getServiceAlertsModelForSituations:(NSArray*)situations {

    OBAServiceAlertsModel * model = [[OBAServiceAlertsModel alloc] init];

    model.totalCount = [situations count];
    
    NSInteger maxUnreadSeverityValue = -99;
    NSInteger maxSeverityValue = -99;
    
    for (OBASituationV2 * situation in situations) {
        NSString * severity = situation.severity;
        NSInteger severityValue = [situation severityAsNumericValue];

        if (![self isVisitedSituationWithId:situation.situationId]) {
            model.unreadCount += 1;
            
            if (!model.unreadMaxSeverity || severityValue > maxUnreadSeverityValue) {
                model.unreadMaxSeverity = severity;
                maxUnreadSeverityValue = severityValue;
            }
        }
        
        if (!model.maxSeverity || severityValue > maxSeverityValue) {
            model.maxSeverity = severity;
            maxSeverityValue = severityValue;
        }
    }    
    
    return model;
}

- (void)setVisited:(BOOL)visited forSituationWithId:(NSString*)situationId {
    
    BOOL prevVisited = [_visitedSituationIds containsObject:situationId];

    if (visited == prevVisited) {
        return;
    }

    if (visited) {
        [_visitedSituationIds addObject:situationId];
    }
    else {
        [_visitedSituationIds removeObject:situationId];
    }

    [_preferencesDao writeVisistedSituationIds:_visitedSituationIds];
}

#pragma mark - Custom API Server

- (void)addCustomApiUrl:(NSString *)customApiUrl {

    if (!customApiUrl) {
        return;
    }

    NSString *existingCustomApiUrl = nil;

    for (NSString *recentCustomApiUrl in _mostRecentCustomApiUrls) {
        if ([recentCustomApiUrl isEqualToString:customApiUrl]) {
            existingCustomApiUrl = customApiUrl;
            break;
        }
    }

    if (existingCustomApiUrl) {
        [_mostRecentCustomApiUrls removeObject:existingCustomApiUrl];
        [_mostRecentCustomApiUrls insertObject:existingCustomApiUrl atIndex:0];
    }
    else {
        [_mostRecentCustomApiUrls insertObject:customApiUrl atIndex:0];
    }

    NSInteger over = [_mostRecentCustomApiUrls count] - kMaxEntriesInMostRecentList;
    for (NSInteger i=0; i<over; i++) {
        [_mostRecentCustomApiUrls removeObjectAtIndex:_mostRecentCustomApiUrls.count - 1];
    }

    [_preferencesDao writeMostRecentCustomApiUrls:_mostRecentCustomApiUrls];
}

- (NSString*)normalizedAPIServerURL {
    NSString *apiServerName = nil;

    if (self.readCustomApiUrl.length > 0) {
        if ([self.readCustomApiUrl hasPrefix:@"http://"] || [self.readCustomApiUrl hasPrefix:@"https://"]) {
            apiServerName = self.readCustomApiUrl;
        }
        else {
            apiServerName = [NSString stringWithFormat:@"http://%@", self.readCustomApiUrl];
        }
    }
    else if (self.region) {
        apiServerName = self.region.obaBaseUrl;
    }

    if ([apiServerName hasSuffix:@"/"]) {
        apiServerName = [apiServerName substringToIndex:apiServerName.length - 1];
    }

    return apiServerName;
}

- (NSString*)readCustomApiUrl {
    return [_preferencesDao readCustomApiUrl];
}

- (void)writeCustomApiUrl:(NSString*)customApiUrl {
    [_preferencesDao writeCustomApiUrl:customApiUrl];
}

@end

