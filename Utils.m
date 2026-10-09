#import "Utils.h"
#import <math.h>
BOOL needsRefresh;

NSUInteger findFirstOpenIndexInListStartingAt(NSArray *list, SBHIconGridSize gridSize, int start) {
    if (gridSize.columns == 0 || gridSize.rows == 0) return 0;

    long long totalCells = (long long)gridSize.columns * gridSize.rows;
    int size = (gridSize.columns >= 100 || gridSize.rows >= 100) ? 500 : (int)totalCells;
    if (size <= 0) return 0;

    //create an array that will store icon indexes
    BOOL helperBoolArray[size];

    for (int i = 0; i < size; i++) {
        helperBoolArray[i] = NO;
    }

    //loop through the array, and place all existing icons at their preferred(custom) indexes
    for (int i = 0; i < [list count]; i++) {
        SBIcon *icon = list[i];

        if ([icon isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) continue;

        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        if (prefs == nil || prefs.gridSize.columns == 0 || prefs.gridSize.rows == 0) continue;

        // Ignore stale saved positions instead of indexing outside the occupancy array.
        NSUInteger idx = prefs.index;
        if (idx >= (NSUInteger)size) continue;

        for (int k = 0; k < prefs.gridSize.rows; k++) {
            for (int j = 0; j < prefs.gridSize.columns; j++) {
                long long tempIdx = (long long)idx + j + ((long long)k * gridSize.columns);
                if (tempIdx >= 0 && tempIdx < size) {
                    helperBoolArray[tempIdx] = YES;
                }
            }
        }
    }

    //find the first open index from start
    if (start < 0) start = 0;
    for (int i = start; i < size; i++) {
        if (!helperBoolArray[i]) {
            return i;
        }
    }

    return 0;
}
//checks if a give grid cell index is valid for an icon
BOOL checkValidIndexForIconSize(SBIconListGridCellInfo *info, SBHIconGridSize writeSize, long long writeIndex) {
    int cols = info.gridSize.columns;
    int rows = info.gridSize.rows;
    if (cols <= 0 || rows <= 0 || writeSize.columns == 0 || writeSize.rows == 0 || writeIndex < 0) return NO;

    long long totalLength = (long long)cols * rows;
    if (writeIndex >= totalLength) return NO;

    //already has an icon in that spot
    if ([info iconIndexForGridCellIndex:(NSUInteger)writeIndex] < (NSUInteger)totalLength) return NO;
    //doesnt fit horizontally(example: a 2x2 widget placed with top left corner in the far right)
    if (((writeIndex % cols) + writeSize.columns) > cols) return NO;
    //doesnt fit vertically(example: a 2x2 widget placed with top left corner in the bottom row)
    if (((writeIndex / cols) + writeSize.rows) > rows) return NO;

    //check every spot on the widget and see if theres already an icon there
    for (int j = 0; j < writeSize.rows; j++) {
        for (int k = 0; k < writeSize.columns; k++) {
            long long tempIdx = writeIndex + ((long long)j * cols) + k;
            if (tempIdx < 0 || tempIdx >= totalLength) return NO;
            if ([info iconIndexForGridCellIndex:(NSUInteger)tempIdx] < totalLength) return NO;
        }
    }

    return YES;
}

//creates a new entry for a given icon
void createNewLocationPrefs(SBIconListModel *model, SBIcon *icon, long long idx) {
    GriddyIconLocationPreferences *prefs = [[GriddyIconLocationPreferences alloc] init];
    prefs.index = idx;
    prefs.ogIndex = prefs.index;
    //turns out gridSizeForGridSizeClass doesn't exist on iOS 15.0 and lower, who knew
    //will make this a bit nicer int he future
    if ([model respondsToSelector:@selector(gridSizeForGridSizeClass:)]) {
        prefs.gridSize = [model gridSizeForGridSizeClass:icon.gridSizeClass];
    } else {
        switch(icon.gridSizeClass) {
        case 0:
            [prefs setGridSizeColumns:1 rows:1];
            break;
        case 1:
            prefs.gridSize = model.iconGridSizeClassSizes.small;
            break;
        case 2:
            prefs.gridSize = model.iconGridSizeClassSizes.medium;
            break;
        case 3:
            prefs.gridSize = model.iconGridSizeClassSizes.large;
            break;
        case 4:
            prefs.gridSize = model.iconGridSizeClassSizes.newsLargeTall;
            break;
        case 5:
            prefs.gridSize = model.iconGridSizeClassSizes.extraLarge;
            break;
        default:
            [prefs setGridSizeColumns:1 rows:1];
            break;
        }
    }
    //place icon at the end of priority for its given class
    prefs.priority = [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")] ? 99 : 999;


    locationPrefs[icon.uniqueIdentifier] = prefs;
}

NSArray *reorderIconListBasedOnCustomIndex(NSArray *iconList, int size) {
    if (size <= 0) return iconList;

    //create a temporary array that will hold icon entries
    int tempArr[size];
    for (int i = 0; i < size; i++) {
        tempArr[i] = -1;
    }

    // Preserve every icon while resolving stale and duplicate saved indexes safely.
    NSMutableArray *overflowIcons = [NSMutableArray array];
    for (int i = 0; i < [iconList count]; i++) {
        SBIcon *icon = iconList[i];
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        NSUInteger preferredIndex = prefs ? prefs.index : (NSUInteger)size;
        int target = preferredIndex < (NSUInteger)size ? (int)preferredIndex : 0;

        if (tempArr[target] != -1) {
            int candidate = target;
            while (candidate < size && tempArr[candidate] != -1) candidate++;
            if (candidate == size) {
                candidate = 0;
                while (candidate < target && tempArr[candidate] != -1) candidate++;
            }
            if (candidate >= size || tempArr[candidate] != -1) {
                [overflowIcons addObject:icon];
                continue;
            }
            target = candidate;
        }
        tempArr[target] = i;
    }

    // Put grid-addressable icons in grid order, then retain any overflow icons.
    NSMutableArray *newList = [[NSMutableArray alloc] init];
    for (int i = 0; i < size; i++) {
        if (tempArr[i] != -1) {
            SBIcon *icon = iconList[tempArr[i]];
            [newList addObject:icon];
        }
    }
    [newList addObjectsFromArray:overflowIcons];

    // Assign priorities in display order, tolerating missing preference entries.
    int widgetCount = 0;
    for (int i = 0; i < [newList count]; i++) {
        SBIcon *icon = newList[i];
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        if ([icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
            if (prefs) prefs.priority = widgetCount;
            widgetCount++;
        } else if (prefs) {
            prefs.priority = 200 + (i - widgetCount);
        }
    }

    //save to nsuserdefaults
    NSMutableDictionary *tempDict = [[NSMutableDictionary alloc] init];
    for (NSString *key in locationPrefs) {
        tempDict[key] = [NSNumber numberWithUnsignedLongLong:((GriddyIconLocationPreferences *)locationPrefs[key]).index];
    }

    [userDefaults setObject:tempDict forKey:((screenOrientation == 0 ? @"GriddyPortraitSave" : @"GriddyLandscapeSave"))];

    return newList;
}

NSArray *patchGridCellInfoForIconList(NSArray *staticIconList, SBIconListGridCellInfo *info, SBIconListModel *model) {
    NSMutableArray *iconList = [staticIconList mutableCopy];
    if (info.gridSize.columns == 0 || info.gridSize.rows == 0) return staticIconList;
    if (info.gridSize.columns > 100 || info.gridSize.rows > 100) return staticIconList;
    [info clearAllIconAndGridCellIndexes];

    BOOL shouldPushDraggedIcons = YES;
    if ([draggedIcons count] > 0 && !creatingNewIcon) {
        for (int i = 0; i < [draggedIcons count]; i++) {
            if (![draggedIcons[i] isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")] && ![staticIconList containsObject:draggedIcons[i]]) {
                shouldPushDraggedIcons = NO;
                break;
            }
        }
    } else {
        shouldPushDraggedIcons = NO;
    }

    //moved dragged icons up in priority to be rendered first
    if (shouldGivePriority && shouldPushDraggedIcons) {
        needsRefresh = YES;
        model.griddyNeedsRefreshFolderImage = YES;
        SBIcon *tempIcon;
        for (int i = 0; i < [draggedIcons count]; i++) {
            tempIcon = draggedIcons[i];
            if (![iconList containsObject:tempIcon]) continue;

            GriddyIconLocationPreferences *prefs = locationPrefs[tempIcon.uniqueIdentifier];
            if (prefs) prefs.priority = 100+i;

            //if the last existing icon in dragged is a placeholder, this means that the "real" icons have been placed already
            if ([tempIcon isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) {
                if ([draggedIcons count] == 1) [draggedIcons removeAllObjects];
            } else {
                [draggedIcons removeObject:tempIcon];
                i--;
            }
            if ([draggedIcons count] == 0) shouldRedrawList = YES;
        }
        if ([draggedIcons count] == 1 && [draggedIcons[0] isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) [draggedIcons removeAllObjects];
    } else if ([draggedIcons count] > 0) {
        //"real" icons havent been placed yet, so we need to bump the placeholder in priority
        needsRefresh = YES;
        SBIcon *tempIcon;
        for (int i = 0; i < [draggedIcons count]; i++) {
            tempIcon = draggedIcons[i];
            if ([iconList containsObject:tempIcon] && [tempIcon isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) {
                GriddyIconLocationPreferences *prefs = locationPrefs[tempIcon.uniqueIdentifier];
                if (prefs) prefs.priority = 100+i;
            }
        }
    }

    //reorder the icon list based on priority, not an efficient sort but it works
    if (needsRefresh) {
        needsRefresh = NO;
        int size = [iconList count];
        BOOL swapFlag = NO;
        for (int i = 0; i < size; i++) {
            swapFlag = NO;
            for (int j = 0; j < size - i - 1; j++) {
                GriddyIconLocationPreferences *pref1 = locationPrefs[((SBIcon *)iconList[j]).uniqueIdentifier];
                if (pref1 == nil) break;
                GriddyIconLocationPreferences *pref2 = locationPrefs[((SBIcon *)iconList[j+1]).uniqueIdentifier];
                if (pref2 == nil) break;
                if (pref1.priority > pref2.priority) {
                    SBIcon *temp = iconList[j];
                    iconList[j] = iconList[j+1];
                    iconList[j+1] = temp;
                    swapFlag = true;
                }
            }
            if (!swapFlag) break;
        }
    }

    //this for loop is responsible for actually laying out the icons
    for (int i = 0; i < [iconList count]; i++) {
        SBIcon *icon = iconList[i];

        //mark folders to also support custom layouts
        if ([icon isKindOfClass:NSClassFromString(@"SBFolderIcon")]) {
            SBFolder *folder = ((SBFolderIcon *)icon).folder;
            for (int i = 0; i < [folder.lists count]; i++) {
                SBIconListModel *model = folder.lists[i];
                model.griddyShouldPatch = YES;
            }
        }

        //if, for some reason, we dont have an entry for an icon, we create a new one
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        if (!prefs)  {
            createNewLocationPrefs(model, icon, (proposedIndex == -1) ? findFirstOpenIndexInListStartingAt(iconList, info.gridSize, 0) : proposedIndex);
            prefs = locationPrefs[icon.uniqueIdentifier];
        }

        NSUInteger writeIndex = prefs.index;
        SBHIconGridSize writeSize = prefs.gridSize;
    

        long long totalCells = (long long)info.gridSize.columns * info.gridSize.rows;
        if (totalCells > 0 && writeIndex >= (NSUInteger)totalCells) writeIndex = 0;
        long long attempts = 0;
        while (!checkValidIndexForIconSize(info, writeSize, (long long)writeIndex) && attempts < totalCells) {
            needsRefresh = YES;
            writeIndex++;
            if ((long long)writeIndex >= totalCells) writeIndex = 0;
            attempts++;
        }
        
        // Do not write grid cells if no valid position could be found for this icon.
        if (!checkValidIndexForIconSize(info, writeSize, (long long)writeIndex)) continue;

        //only save to location prefs if we have nothing in dragged
        //v1.0.3 added isEditingLayout to support Atria glitch where on startup
        //grid would be smaller than it should and it would  overwrite locations
        if ([draggedIcons count] == 0 && isEditingLayout) {
            prefs.index = writeIndex;
            prefs.ogIndex = writeIndex;
        }

        NSMutableArray <NSNumber *> *writeIndexList = [NSMutableArray new];

        //go through and grab every grid index for the icon, whihc we will save as the specific icon index
        for (int j = 0; j < writeSize.rows; j++) {
            for (int k = 0; k < writeSize.columns; k++) {
                NSUInteger tempIdx = (writeIndex + (info.gridSize.columns * j)) + k;
                if (tempIdx < (NSUInteger)(info.gridSize.columns * info.gridSize.rows)) {
                    [writeIndexList addObject:[NSNumber numberWithUnsignedLongLong:tempIdx]];
                }
            }
        }
        

        //convert the index in the icon list(ordered by priority) to the actual list that is saved on the SBIconListModel instance
        NSUInteger realIdx = [staticIconList indexOfObject:icon];
        if (realIdx == NSNotFound) continue;

        // write locations to the SBIconGridCellInfo
        for (int k = 0; k < [writeIndexList count]; k++) {
            [info setIconIndex:realIdx forGridCellIndex:(writeIndexList[k]).unsignedIntegerValue];
        }
        [info setGridCellIndex:writeIndex forIconIndex:realIdx];
    }

    //if we need to sort, sort and redraw
    if (shouldRedrawList) {
        iconList = [reorderIconListBasedOnCustomIndex(iconList, info.gridSize.columns * info.gridSize.rows) mutableCopy]; 
        shouldRedrawList = NO;
        return patchGridCellInfoForIconList(iconList, info, model);
    }
    
    return staticIconList;
}

// Apply the saved layout to iOS 17's speculative drag layout. Unlike the normal layout path,
// this function must not alter saved positions, priorities, or the drag session's shared state.
void applyGriddyLayoutToGridCellInfo(NSArray *iconList, SBIconListGridCellInfo *info) {
    if (![iconList isKindOfClass:[NSArray class]] || info == nil) return;

    long long columns = info.gridSize.columns;
    long long rows = info.gridSize.rows;
    long long total = columns * rows;
    if (columns <= 0 || rows <= 0 || total <= 0 || total > 4096) return;

    [info clearAllIconAndGridCellIndexes];

    NSMutableArray<NSDictionary *> *placements = [NSMutableArray arrayWithCapacity:iconList.count];
    for (NSUInteger i = 0; i < iconList.count; i++) {
        SBIcon *icon = iconList[i];
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        if (prefs == nil) continue;
        [placements addObject:@{
            @"iconIndex": @(i),
            @"cell": @(prefs.index),
            @"width": @(MAX(1, prefs.gridSize.columns)),
            @"height": @(MAX(1, prefs.gridSize.rows)),
            @"priority": @(prefs.priority)
        }];
    }
    [placements sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"priority"] compare:b[@"priority"]];
    }];

    BOOL occupied[4096];
    for (long long i = 0; i < total; i++) occupied[i] = NO;

    for (NSDictionary *entry in placements) {
        NSUInteger iconIndex = [entry[@"iconIndex"] unsignedIntegerValue];
        long long requested = [entry[@"cell"] longLongValue];
        long long width = [entry[@"width"] longLongValue];
        long long height = [entry[@"height"] longLongValue];
        if (iconIndex >= iconList.count || requested < 0 || requested >= total) continue;

        for (long long attempt = 0; attempt < total; attempt++) {
            long long cell = (requested + attempt) % total;
            long long column = cell % columns;
            long long row = cell / columns;
            if (column + width > columns || row + height > rows) continue;

            BOOL free = YES;
            for (long long dy = 0; dy < height && free; dy++) {
                for (long long dx = 0; dx < width; dx++) {
                    if (occupied[(row + dy) * columns + column + dx]) {
                        free = NO;
                        break;
                    }
                }
            }
            if (!free) continue;

            for (long long dy = 0; dy < height; dy++) {
                for (long long dx = 0; dx < width; dx++) {
                    NSUInteger target = (NSUInteger)((row + dy) * columns + column + dx);
                    occupied[target] = YES;
                    [info setIconIndex:iconIndex forGridCellIndex:target];
                }
            }
            [info setGridCellIndex:(NSUInteger)cell forIconIndex:iconIndex];
            break;
        }
    }
}

// Render an iOS 17 folder preview with the modern cache accessor rather than the removed
// _cachedMiniGridImages/_genericMiniGridImage ivars. Return SpringBoard's original image whenever
// the layout or any mini-icon image is not ready; never publish a partially drawn preview.
SBIconGridImage *griddyRenderFolderPage(id cache, NSUInteger pageIndex, SBFolderIcon *folderIcon, SBIconGridImage *original) {
    if (![NSThread isMainThread] || cache == nil || original == nil || folderIcon == nil) return original;
    if (![original isKindOfClass:NSClassFromString(@"SBIconGridImage")]) return original;
    NSArray *pages = folderIcon.folder.lists;
    if (pageIndex >= pages.count) return original;

    SBIconListModel *model = pages[pageIndex];
    model.griddyShouldPatch = YES;
    if (!patchFoldersChecked) {
        shouldPatchFolderIcon = determineFolderPatching();
        patchFoldersChecked = YES;
    }
    if (!shouldPatchFolderIcon || !hasLoadedPrefs || model.icons.count == 0) return original;

    SBIconGridImage *cached = folderImageCache[model];
    if (cached && !model.griddyNeedsRefreshFolderImage) return cached;

    id layoutObject = [cache respondsToSelector:@selector(listLayout)] ? [cache listLayout] : original.listLayout;
    if (layoutObject == nil) layoutObject = original.listLayout;
    if (![layoutObject respondsToSelector:@selector(folderIconVisualConfiguration)] ||
        ![layoutObject respondsToSelector:@selector(iconImageInfo)] ||
        ![cache respondsToSelector:@selector(gridCellImageForIcon:)]) return original;

    SBIconListGridLayout *layout = (SBIconListGridLayout *)layoutObject;
    SBHFolderIconVisualConfiguration *configuration = layout.folderIconVisualConfiguration;
    if (configuration == nil) return original;
    CGSize cellSize = configuration.gridCellSize;
    CGSize spacing = configuration.gridCellSpacing;
    SBIconImageInfo imageInfo = layout.iconImageInfo;
    if (cellSize.width <= 0 || cellSize.height <= 0 ||
        imageInfo.size.width <= 0 || imageInfo.size.height <= 0) return original;

    CGSize step = CGSizeMake(cellSize.width + spacing.width, cellSize.height + spacing.height);
    if (step.width <= 0 || step.height <= 0) return original;
    CGFloat gridWidth = imageInfo.size.width * 0.75;
    CGFloat gridHeight = imageInfo.size.height * 0.75;
    NSInteger columns = (NSInteger)floor((gridWidth + spacing.width) / step.width);
    NSInteger rows = (NSInteger)floor((gridHeight + spacing.height) / step.height);
    if (columns < 1) columns = 1;
    if (rows < 1) rows = 1;
    if (columns > 8) columns = 8;
    if (rows > 8) rows = 8;
    if (model.gridSize.columns > 0 && model.gridSize.columns < columns) columns = model.gridSize.columns;
    if (model.gridSize.rows > 0 && model.gridSize.rows < rows) rows = model.gridSize.rows;

    CGSize canvas = CGSizeMake((columns - 1) * step.width + cellSize.width,
                               (rows - 1) * step.height + cellSize.height);
    if (canvas.width <= 0 || canvas.height <= 0) return original;

    NSMutableArray<NSDictionary *> *ordered = [NSMutableArray arrayWithCapacity:model.icons.count];
    for (NSUInteger i = 0; i < model.icons.count; i++) {
        SBIcon *icon = model.icons[i];
        if ([icon isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) continue;
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        if (prefs == nil) return original;
        [ordered addObject:@{@"icon": icon, @"prefs": prefs, @"order": @(i)}];
    }
    [ordered sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        GriddyIconLocationPreferences *pa = a[@"prefs"];
        GriddyIconLocationPreferences *pb = b[@"prefs"];
        if (pa.priority < pb.priority) return NSOrderedAscending;
        if (pa.priority > pb.priority) return NSOrderedDescending;
        return [a[@"order"] compare:b[@"order"]];
    }];

    BOOL occupied[64];
    for (NSInteger i = 0; i < 64; i++) occupied[i] = NO;
    UIGraphicsBeginImageContextWithOptions(canvas, NO, original.scale);
    if (UIGraphicsGetCurrentContext() == NULL) {
        UIGraphicsEndImageContext();
        return original;
    }

    BOOL complete = YES;
    NSUInteger drawn = 0;
    NSInteger modelColumns = model.gridSize.columns;
    if (modelColumns <= 0) modelColumns = columns;
    for (NSDictionary *entry in ordered) {
        SBIcon *icon = entry[@"icon"];
        GriddyIconLocationPreferences *prefs = entry[@"prefs"];
        if ([cache respondsToSelector:@selector(shouldSkipGridCellImageForIcon:)] &&
            [cache shouldSkipGridCellImageForIcon:icon]) continue;

        UIImage *mini = [cache gridCellImageForIcon:icon];
        if (mini == nil) { complete = NO; break; }

        NSInteger desiredRow = (NSInteger)(prefs.index / modelColumns);
        NSInteger desiredColumn = (NSInteger)(prefs.index % modelColumns);
        NSInteger startCell = (desiredRow < rows && desiredColumn < columns)
            ? desiredRow * columns + desiredColumn : -1;
        NSInteger chosen = -1;
        for (NSInteger attempt = 0; attempt < columns * rows; attempt++) {
            NSInteger candidate = startCell >= 0 ? (startCell + attempt) % (columns * rows) : attempt;
            if (!occupied[candidate]) { chosen = candidate; break; }
        }
        if (chosen < 0) { complete = NO; break; }
        occupied[chosen] = YES;
        NSInteger row = chosen / columns;
        NSInteger column = chosen % columns;
        [mini drawInRect:CGRectMake(column * step.width, row * step.height, cellSize.width, cellSize.height)];
        drawn++;
    }

    UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!complete || drawn == 0 || rendered.CGImage == NULL) return original;

    SBIconGridImage *result = [[NSClassFromString(@"SBIconGridImage") alloc]
        initWithCGImage:rendered.CGImage scale:rendered.scale orientation:UIImageOrientationUp];
    if (result == nil) return original;
    if ([result respondsToSelector:@selector(setListLayout:)]) result.listLayout = original.listLayout ?: layoutObject;
    folderImageCache[model] = result;
    model.griddyNeedsRefreshFolderImage = NO;
    return result;
}

//used to calculate the grid cell index for a point and icon size
//note: this function always returns the index for the top left corner of an icon
long long calculateGridCellIndexForPoint(CGPoint point, CGRect workingSize, SBHIconGridSize workingGridSize, SBHIconGridSize indexOffset, SBHIconGridSize iconSize) {
    if (workingGridSize.columns == 0 || workingGridSize.rows == 0 || iconSize.columns == 0 || iconSize.rows == 0) {
        return proposedIndex;
    }

    float iconWidth = workingSize.size.width / workingGridSize.columns;
    float iconHeight = workingSize.size.height / workingGridSize.rows;
    if (iconWidth <= 0 || iconHeight <= 0) return proposedIndex;
    if (point.x < workingSize.origin.x || point.y < workingSize.origin.y ||
        point.x >= CGRectGetMaxX(workingSize) || point.y >= CGRectGetMaxY(workingSize)) {
        return proposedIndex;
    }

    // Use signed intermediates so negative touch coordinates or offsets cannot wrap.
    long long column = (long long)((point.x - workingSize.origin.x) / iconWidth);
    long long row = (long long)((point.y - workingSize.origin.y) / iconHeight);
    long long tempIdx = column + (row * workingGridSize.columns);
    tempIdx -= indexOffset.columns;
    tempIdx -= (long long)indexOffset.rows * workingGridSize.columns;

    long long totalLength = (long long)workingGridSize.columns * workingGridSize.rows;
    if (tempIdx < 0 || tempIdx >= totalLength) return proposedIndex;
    if ((tempIdx % workingGridSize.columns) + iconSize.columns > workingGridSize.columns) return proposedIndex;
    if ((tempIdx / workingGridSize.columns) + iconSize.rows > workingGridSize.rows) return proposedIndex;

    return tempIdx;
}

//check different folder tweaks to determine if we should patch folder icons or not
BOOL determineFolderPatching() {
    BOOL tempShouldPatch;
    // Primal Folders 2 check, big thanks to Ichitaso for this snippet
    // https://github.com/ichitaso
    NSDictionary *primalFolder = [NSDictionary dictionaryWithContentsOfFile:jbroot(@"/var/mobile/Library/Preferences/com.ichitaso.primalfolder2.plist")];
    BOOL hasPrimalFolders = [[NSFileManager defaultManager] fileExistsAtPath:jbroot(@"/Library/MobileSubstrate/DynamicLibraries/PrimalFolder2.dylib")];  
    
    if (!hasPrimalFolders || primalFolder == nil) {
            tempShouldPatch = YES;
    } else {
        if ([primalFolder[@"keepFolder"] boolValue]) {
            tempShouldPatch = YES;
        } else {
            tempShouldPatch = NO;
        }
    }
    if (!tempShouldPatch) return NO;

    //Hello Folder check, big thanks to w2599 for this snippet
    //https://github.com/w2599
    NSDictionary *helloFolder = [NSDictionary dictionaryWithContentsOfFile:jbroot(@"/var/mobile/Library/Preferences/cn.zqbb.0rzFolder.plist")];
    if (helloFolder == nil) {
        tempShouldPatch = YES;
    } else {
        tempShouldPatch = ![helloFolder[@"wantsEnable"] boolValue];
    }
    if (!tempShouldPatch) return NO;

    //Bolders Reborn check
    NSDictionary *boldersReborn = [NSDictionary dictionaryWithContentsOfFile:jbroot(@"/var/mobile/Library/Preferences/com.nightwind.boldersrebornprefs.plist")];
    BOOL hasBoldersReborn = [[NSFileManager defaultManager] fileExistsAtPath:jbroot(@"/Library/MobileSubstrate/DynamicLibraries/BoldersReborn.dylib")];  
    if (!hasBoldersReborn || boldersReborn == nil) {
        tempShouldPatch = YES;
    } else {
        tempShouldPatch = ![boldersReborn[@"tweakEnabled"] boolValue];
    }
    if (!tempShouldPatch) return NO;

    return YES;
}
//moving save data over to it's own .plist
void transferGriddySave() {
    NSUserDefaults *oldUserDefaults = [NSUserDefaults standardUserDefaults];
    portraitSavedDict = [oldUserDefaults dictionaryForKey:@"GriddyPortraitSave"];
    landscapeSavedDict = [oldUserDefaults dictionaryForKey:@"GriddyLandscapeSave"];

    NSUserDefaults *newUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.mikifp.griddy"];
    NSMutableDictionary *tempDict = [[NSMutableDictionary alloc] init];
    //transfer portrait save
    for (NSString *key in portraitSavedDict) {
        tempDict[key] = portraitSavedDict[key];
    }
    [newUserDefaults setObject:tempDict forKey:@"GriddyPortraitSave"];

    [tempDict removeAllObjects];
    //transfer lansdscape save
    for (NSString *key in landscapeSavedDict) {
        tempDict[key] = landscapeSavedDict[key];
    }
    [newUserDefaults setObject:tempDict forKey:@"GriddyLandscapeSave"];

    [oldUserDefaults removeObjectForKey:@"GriddyPortraitSave"];
    [oldUserDefaults removeObjectForKey:@"GriddyLandscapeSave"];
}

//generate new image for a folder icon
//code is essentially the same as it used to be
//however, version 1.0.4 caches the generated images and only creates a new one if it needs to
SBIconGridImage *generateNewFolderImageForModel(SBIconListModel *model, SBIconGridImage *gridImageRef, SBFolderIconImageCache *imageCache, SBIconListGridLayout *miniIconLayout) {
    griddyImageSuccess = YES;

    if (!hasLoadedPrefs) griddyImageSuccess = NO;

    NSMapTable *miniGridImages = [imageCache valueForKey:@"_cachedMiniGridImages"];

    SBHFolderIconVisualConfiguration *miniIconConfiguration = miniIconLayout.folderIconVisualConfiguration;

    CGSize size = miniIconConfiguration.gridCellSize;
    CGSize spacing = miniIconConfiguration.gridCellSpacing;

    CGSize perIconSpace = CGSizeMake(size.width + spacing.width, size.height + spacing.height);
    CGSize newSize;

    newSize = CGSizeMake((perIconSpace.width * (gridImageRef.numberOfRows-1)) + size.width, (perIconSpace.height *(gridImageRef.numberOfColumns-1)) + size.height);

    UIGraphicsBeginImageContextWithOptions(newSize, NO, gridImageRef.scale);

    if (UIGraphicsGetCurrentContext() == nil) {
        griddyImageSuccess = NO;
        return gridImageRef;
    }

    for(SBIcon *icon in model.icons) {
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        if (prefs == nil) {
            griddyImageSuccess = NO;
            continue;
        }

        int row = prefs.index / gridImageRef.numberOfRows;
        int col = prefs.index % gridImageRef.numberOfColumns;

        UIImage *img = [miniGridImages objectForKey:icon];
        
        if (img == nil) {
            img = [imageCache valueForKey:@"_genericMiniGridImage"];
            continue;
        }

        [img drawInRect:CGRectMake(col * perIconSpace.width, row * perIconSpace.height, size.width, size.height)];
    }

    UIImage *newImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [gridImageRef initWithCGImage:newImg.CGImage scale:gridImageRef.scale orientation:UIImageOrientationUp];
}