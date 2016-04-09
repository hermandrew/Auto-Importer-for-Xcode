//
//  LAFImportGroupMapping.h
//  AutoImporter
//
//  Created by Andrew Herman on 4/9/16.
//  Copyright © 2016 luisfloreani.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LAFImportGroupMapping : NSObject

+ (instancetype)sharedMapping;
- (NSDictionary *)allMappings;
- (void)addMappingForProjectAtPath:(NSString *)filePath;

@end
