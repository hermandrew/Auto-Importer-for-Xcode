//
//  LAFImportGroupMapping.m
//  AutoImporter
//
//  Created by Andrew Herman on 4/9/16.
//  Copyright © 2016 luisfloreani.com. All rights reserved.
//

#import "LAFImportGroupMapping.h"

@interface LAFImportGroupMapping()

@property (strong, nonatomic) NSMutableDictionary *mappings;

@end

@implementation LAFImportGroupMapping

+ (instancetype)sharedMapping
{
    static LAFImportGroupMapping *sharedMapping;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMapping = [[self alloc] init];
    });
    
    return sharedMapping;
}

- (void)addMappingForProjectAtPath:(NSString *)filePath
{
    NSLog(@"File Path: %@", filePath);
    
    if (self.mappings[filePath])
    {
        return;
    }
    
    NSMutableDictionary *theseMappings = [NSMutableDictionary dictionary];
    
    NSString *dirPath = [filePath stringByDeletingLastPathComponent];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:[NSURL URLWithString:dirPath]
                                          includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        errorHandler:^BOOL(NSURL *url, NSError *error)
    {
        if (error) {
            NSLog(@"[Error] %@ (%@)", error, url);
            return NO;
        }
        
        return YES;
    }];
    
    NSMutableArray *mutableFileURLs = [NSMutableArray array];
    for (NSURL *fileURL in enumerator) {
        NSString *filename;
        [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];
        
        NSNumber *isDirectory;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        
        if (!isDirectory.boolValue)
        {
            if ([filename isEqualToString:@"import_config.plist"])
            {
                NSDictionary *theseConfigs = [NSDictionary dictionaryWithContentsOfURL:fileURL];
                if (theseConfigs && theseConfigs.count)
                {
                    [theseMappings addEntriesFromDictionary:theseConfigs];
                }
            }
        }
        
        if (![isDirectory boolValue])
        {
            [mutableFileURLs addObject:fileURL];
        }
    }
    
    if (!self.mappings && (theseMappings.count > 0))
    {
        self.mappings = [NSMutableDictionary dictionaryWithDictionary:theseMappings];
    }
}

- (NSDictionary *)allMappings
{
    if (self.mappings)
    {
        return self.mappings;
    }
    else
    {
        return @
        {
            @"View" : @"Views",
            @"ViewController" : @"View Controllers"
        };
    }
}

@end
