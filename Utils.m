#import "Utils.h"
BOOL needsRefresh;

NSUInteger findFirstOpenIndexInListStartingAt(NSArray *list, SBHIconGridSize gridSize, int start) {
    if (gridSize.columns == 0 || gridSize.rows == 0) return 0;

    int size = gridSize.columns * gridSize.rows;
    if (gridSize.columns >= 100 || gridSize.rows >= 100) size = 500;
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

    int totalLength = cols * rows;
    if (writeIndex >= totalLength) return NO;

    //already has an icon in that spot
    if ([info iconIndexForGridCellIndex:(NSUInteger)writeIndex] < totalLength) return NO;
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
            if (candidate >= size || tempArr[candidate] != -1) continue;
            target = candidate;
        }
        tempArr[target] = i;
    }

    //go through the temporary array, and take any icons you find along the way, puttung them in a new array
    NSMutableArray *newList = [[NSMutableArray alloc] init];
    for (int i = 0; i < size; i++) {
        if (tempArr[i] != -1) {
            SBIcon *icon = iconList[tempArr[i]];
            [newList addObject:icon];
        }
    }
    //assign priorities to icons, in order of them showing up as well as based on their class
    int widgetCount = 0;
    for(int i = 0; i < [newList count]; i++) {
        SBIcon *icon = newList[i];
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        //widgets get 0-99
        if ([icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
            prefs.priority = widgetCount;
            widgetCount++;
        }
        //normal icons get 200+
        else {
            prefs.priority = 200+(i-widgetCount);
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
            prefs.priority = 100+i;

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
                prefs.priority = 100+i;
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