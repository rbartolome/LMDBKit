//
//  LMDBI+NSPropertyListSerialization.h
//
//  Created by Raphael Bartolome on 06.05.13.
//  Copyright (c) 2013 Raphael Bartolome. All rights reserved.
//

#import "LMDBKit.h"

@interface LMDBI (NSPropertyListSerialization)

#pragma mark - Setter Methods
- (BOOL)setObject: (id)object forKey: (NSString *)aKey;

- (BOOL)setData: (NSData *)value forKey:(NSString *)aKey;
- (BOOL)setString: (NSString *)value forKey:(NSString *)aKey;
- (BOOL)setDate: (NSDate *)value forKey:(NSString *)aKey;
- (BOOL)setDictionary: (NSDictionary *)value forKey:(NSString *)aKey;
- (BOOL)setArray: (NSArray *)value forKey:(NSString *)aKey;

- (BOOL)setBool: (BOOL)value forKey:(NSString *)aKey;
- (BOOL)setFloat: (float)value forKey:(NSString *)aKey;
- (BOOL)setInteger: (NSInteger)value forKey:(NSString *)aKey;
- (BOOL)setDouble: (double)value forKey:(NSString *)aKey;

- (BOOL)removeObjectForKey: (NSString *)aKey;

#pragma mark - Getter Methods

- (BOOL)keyExists: (NSString *)key;

- (id)objectForKey: (NSString *)aKey;

- (NSData *)dataForKey: (NSString *)aKey;
- (NSString *)stringForKey: (NSString *)aKey;
- (NSDate *)dateForKey: (NSString *)aKey;
- (NSDictionary *)dictionaryForKey: (NSString *)aKey;
- (NSArray *)arrayForKey: (NSString *)aKey;

- (BOOL)boolForKey: (NSString *)aKey;
- (float)floatForKey: (NSString *)aKey;
- (NSInteger)integerForKey: (NSString *)aKey;
- (double)doubleForKey: (NSString *)aKey;

#pragma mark - Enumeration

- (BOOL)enumerateKeysAndObjectsUsingBlock: (void (^) (id object, NSString *key, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateKeysAndObjectsStartWithKeyString: (NSString *)startKey usingBlock: (void (^) (id object, NSString *key, NSInteger count, BOOL *stop))block;

- (BOOL)enumerateKeysUsingBlock: (void (^) (NSString *key, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateKeysStartWithKeyString: (NSString *)startKey usingBlock: (void (^) (NSString *key, NSInteger count, BOOL *stop))block;

- (BOOL)enumerateObjectsUsingBlock: (void (^) (id object, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateObjectStartWithKeyString: (NSString *)startKey usingBlock: (void (^) (id object, NSInteger count, BOOL *stop))block;


#pragma mark Sorted Set Handling
- (NSInteger)objectCountForKey: (NSString *)key;

- (BOOL)addObject: (id)object forKey: (NSString *)aKey;

- (BOOL)replaceObjectForKey: (NSString *)aKey withObject: (id)object atIndex: (NSInteger)index;
- (BOOL)replaceObject: (id)object withObject: (id)newObject forKey: (NSString *)aKey;

- (BOOL)removeObjectsForKey: (NSString *)aKey;
- (BOOL)removeObject: (id)object forKey: (NSString *)aKey;
- (BOOL)removeObjectForKey: (NSString *)aKey atIndex: (NSInteger)index;

- (NSArray *)objectsForKey: (NSString *)aKey;
- (id)objectForKey: (NSString *)aKey atIndex: (NSInteger)index;
- (id)lastObjectForKey: (NSString *)aKey;
- (id)firstObjectForKey: (NSString *)aKey;

- (BOOL)enumerateObjectsForKey: (NSString *)key usingBlock: (void (^) (id object, NSInteger index, BOOL *stop))block;

@end
