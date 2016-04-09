//
//  LAFIDESourceCodeEditor.m
//  AutoImporter
//
//  Created by Luis Floreani on 10/2/14.
//  Copyright (c) 2014 luisfloreani.com. All rights reserved.
//

#import "LAFIDESourceCodeEditor.h"
#import "MHXcodeDocumentNavigator.h"
#import "DVTSourceTextStorage+Operations.h"
#import "NSTextView+Operations.h"
#import "NSString+Extensions.h"

// Other
#import "LAFImportGroupMapping.h"

NSString * const LAFAddImportOperationImportRegexPattern = @"^#.*(import|include).*[\",<].*[\",>]";
NSString * const LAFImportGroupRegexFormatPattern = @"^\/\/ %@\s?$";
NSString * const LAFImportGroupClassEndingRegexFormatPattern = @"%@.h";

@interface LAFIDESourceCodeEditor()

@property (nonatomic, strong) NSMutableSet *importedCache;

@end

@implementation LAFIDESourceCodeEditor

- (NSString *)importStatementFor:(NSString *)header {
    return [NSString stringWithFormat:@"#import \"%@\"", header];
}

- (void)cacheImports {
    [self invalidateImportsCache];
    
    if (!_importedCache) {
        _importedCache = [NSMutableSet set];
    }
    
    DVTSourceTextStorage *textStorage = [self currentTextStorage];
    [textStorage.string enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if ([self isImportString:line]) {
            [_importedCache addObject:[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }
    }];
}

- (void)invalidateImportsCache {
    [_importedCache removeAllObjects];
}

- (LAFImportResult)importHeader:(NSString *)header {
    return [self addImport:[self importStatementFor:header]];
}

- (BOOL)hasImportedHeader:(NSString *)header {
    return [_importedCache containsObject:[self importStatementFor:header]];
}

- (NSView *)view {
    return [MHXcodeDocumentNavigator currentSourceCodeTextView];
}

- (NSString *)selectedText {
    NSTextView *textView = [MHXcodeDocumentNavigator currentSourceCodeTextView];
    NSRange range = textView.selectedRange;
    return [[textView string] substringWithRange:range];
}

- (void)insertOnCaret:(NSString *)text {
    NSTextView *textView = [MHXcodeDocumentNavigator currentSourceCodeTextView];
    NSRange range = textView.selectedRange;
    [textView insertText:text replacementRange:range];
}

- (void)showAboveCaret:(NSString *)text color:(NSColor *)color {
    NSTextView *currentTextView = [MHXcodeDocumentNavigator currentSourceCodeTextView];
    
    NSRect keyRectOnTextView = [currentTextView mhFrameForCaret];
    
    NSTextField *field = [[NSTextField alloc] initWithFrame:CGRectMake(keyRectOnTextView.origin.x, keyRectOnTextView.origin.y, 0, 0)];
    [field setBackgroundColor:color];
    [field setFont:currentTextView.font];
    [field setTextColor:[NSColor colorWithCalibratedWhite:0.2 alpha:1.0]];
    [field setStringValue:text];
    [field sizeToFit];
    [field setBordered:NO];
    [field setEditable:NO];
    field.frame = CGRectOffset(field.frame, 0, - field.bounds.size.height - 3);
    
    [currentTextView addSubview:field];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSAnimationContext beginGrouping];
        [[NSAnimationContext currentContext] setCompletionHandler:^{
            [field removeFromSuperview];
        }];
        [[NSAnimationContext currentContext] setDuration:1.0];
        [[field animator] setAlphaValue:0.0];
        [NSAnimationContext endGrouping];
    });
}

- (DVTSourceTextStorage *)currentTextStorage {
    if (![[MHXcodeDocumentNavigator currentEditor] isKindOfClass:NSClassFromString(@"IDESourceCodeEditor")]) {
        return nil;
    }
    NSTextView *textView = [MHXcodeDocumentNavigator currentSourceCodeTextView];
    return (DVTSourceTextStorage*)textView.textStorage;
}

- (LAFImportResult)addImport:(NSString *)statement {
    NSString *importGroup = [self importGroupForStatment:statement];
    
    DVTSourceTextStorage *textStorage = [self currentTextStorage];
    BOOL importGroupExists = NO;
    BOOL duplicate = NO;
    NSInteger lastLine = [self appropriateLine:textStorage
                                     statement:statement
                                     duplicate:&duplicate
                                       inGroup:importGroup
                                   groupExists:&importGroupExists];
    
    if (lastLine != NSNotFound) {
        NSString *importString = [NSString stringWithFormat:@"%@\n", statement];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (importGroupExists)
            {
                [textStorage mhInsertString:importString
                                     atLine:lastLine+1];
            }
            else
            {
                NSString *string = [NSString stringWithFormat:@"\n// %@\n%@", importGroup, importString];
                [textStorage mhInsertString:string
                                     atLine:lastLine+1];
            }
        });
    }
    
    if (duplicate) {
        return LAFImportResultAlready;
    } else {
        return LAFImportResultDone;
    }
}

- (NSString *)importGroupForStatment:(NSString *)statement
{
    NSDictionary *importGroups = [[LAFImportGroupMapping sharedMapping] allMappings];
    
    for (NSString *thisKey in importGroups.allKeys)
    {
        NSRegularExpression *headerRegex = [self importGroupHeaderRegex:thisKey];
        NSInteger numberOfMatch = [headerRegex numberOfMatchesInString:statement
                                                               options:0
                                                                 range:NSMakeRange(0, statement.length)];
        if (numberOfMatch)
        {
            return importGroups[thisKey];
        }
    }
    
    return @"Other";
}

- (NSUInteger)appropriateLine:(DVTSourceTextStorage *)source
                    statement:(NSString *)statement
                    duplicate:(BOOL *)duplicate
                      inGroup:(NSString *)group
                  groupExists:(BOOL *)groupExists;
{
    __block NSUInteger lineNumber = NSNotFound;
    __block NSUInteger currentLineNumber = 0;
    __block BOOL foundDuplicate = NO;
    __block BOOL foundGroup = NO;
    __block BOOL continueIncrementing = YES;
    
    [source.string enumerateLinesUsingBlock:^(NSString *line, BOOL *stop)
    {
        if ([self isImportString:line])
        {
            if ([line isEqual:statement])
            {
                foundDuplicate = YES;
                *stop = YES;
                return;
            }
            
            if (continueIncrementing)
            {
                lineNumber = currentLineNumber;
            }
        }
        else if ([self isGroupString:line forGroup:group])
        {
            foundGroup = YES;
        }
        else if (foundGroup)
        {
            continueIncrementing = NO;
        }
        
        currentLineNumber++;
    }];
    
    *groupExists = foundGroup;
    
    if (foundDuplicate) {
        *duplicate = YES;
        return NSNotFound;
    }
    
    //if no imports are present find the first new line.
    if (lineNumber == NSNotFound) {
        currentLineNumber = 0;
        [source.string enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            if (![line mh_isWhitespaceOrNewline]) {
                currentLineNumber++;
            }
            else {
                lineNumber = currentLineNumber;
                *stop = YES;
            }
        }];
    }
    
    return lineNumber;
}

- (NSRegularExpression *)importGroupHeaderRegex:(NSString *)headerEnding
{
    static NSMutableDictionary *regexes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        regexes = [NSMutableDictionary dictionary];
    });
    
    if (!regexes[headerEnding])
    {
        NSString *thisPattern = [NSString stringWithFormat:LAFImportGroupClassEndingRegexFormatPattern, headerEnding];
        regexes[headerEnding] = [[NSRegularExpression alloc] initWithPattern:thisPattern
                                                                     options:NSRegularExpressionAnchorsMatchLines
                                                                       error:nil];
    }
    
    return regexes[headerEnding];
}

- (NSRegularExpression *)importGroupRegex:(NSString *)group
{
    static NSMutableDictionary *regexes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
                  {
                      regexes = [NSMutableDictionary dictionary];
                  });
    
    if (!regexes[group])
    {
        NSString *thisPattern = [NSString stringWithFormat:LAFImportGroupRegexFormatPattern, group];
        regexes[group] = [[NSRegularExpression alloc] initWithPattern:thisPattern
                                                              options:NSRegularExpressionAnchorsMatchLines
                                                                error:nil];
    }
    
    return regexes[group];
}

- (NSRegularExpression *)importRegex {
    static NSRegularExpression *_regex = nil;
    if (!_regex) {
        NSError *error = nil;
        
        _regex = [[NSRegularExpression alloc] initWithPattern:LAFAddImportOperationImportRegexPattern
                                                      options:0
                                                        error:&error];
    }
    return _regex;
}

- (BOOL)isImportString:(NSString *)string {
    NSRegularExpression *regex = [self importRegex];
    NSInteger numberOfMatches = [regex numberOfMatchesInString:string options:0 range:NSMakeRange(0, string.length)];
    return numberOfMatches > 0;
}

- (BOOL)isGroupString:(NSString *)line forGroup:(NSString *)group
{
    NSRegularExpression *regex = [self importGroupRegex:group];
    NSInteger numberOfMatches= [regex numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)];
    return numberOfMatches > 0;
}

@end
