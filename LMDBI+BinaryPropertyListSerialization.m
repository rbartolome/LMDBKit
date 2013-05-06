//
//  LMDBIPList+BinaryPropertyListSerialization.m
//
//  Created by Raphael Bartolome on 06.05.13.
//  Copyright (c) 2013 Raphael Bartolome. All rights reserved.
//

#import "LMDBI+BinaryPropertyListSerialization.h"

@implementation LMDBI (BinaryPropertyListSerialization)

#pragma mark - Private serialize methods

- (NSData *)_dataFromPropertyList: (id)pList;
{
    NSError *error = nil;
    NSData *data = nil;
    
    if(pList)
    {
        data = [NSPropertyListSerialization dataWithPropertyList: pList
                                                          format: NSPropertyListBinaryFormat_v1_0
                                                         options: 0
                                                           error: &error];
    }
    if(error)
        data = nil;
    
    return data;
}

- (id)_objectFromPropertyListData: (NSData *)data;
{
    id returnValue = nil;
    
    if(data)
    {
        NSError *error = nil;
        returnValue = [NSPropertyListSerialization propertyListWithData: data
                                                                options: kCFPropertyListImmutable
                                                                 format: NULL
                                                                  error: &error];
        
        if(error)
        {
            returnValue = nil;
        }
    }
    
    return returnValue;
}

#pragma mark - Setter Methods

- (BOOL)setObject: (id)object forKey: (NSString *)aKey;
{
    BOOL result = YES;
    NSData *data = [self _dataFromPropertyList: object];
    
    if(!data)
    {
        result = NO;
    }
    else
    {
        result = [self storeDataItem: data forKey: NSDataFromString(aKey)];
    }
    
    return result;
}

- (BOOL)setBool: (BOOL)value forKey:(NSString *)aKey;
{
    return [self setObject: [NSNumber numberWithBool: value] forKey: aKey];
}

- (BOOL)setFloat: (float)value forKey:(NSString *)aKey;
{
    return [self setObject: [NSNumber numberWithFloat: value] forKey: aKey];
}

- (BOOL)setInteger: (NSInteger)value forKey:(NSString *)aKey;
{
    return [self setObject: [NSNumber numberWithInteger: value] forKey: aKey];
}

- (BOOL)setDouble: (double)value forKey:(NSString *)aKey;
{
    return [self setObject: [NSNumber numberWithDouble: value] forKey: aKey];
}

- (BOOL)setData: (NSData *)value forKey:(NSString *)aKey;
{
    return [self setObject: value forKey: aKey];
}

- (BOOL)setString: (NSString *)value forKey:(NSString *)aKey;
{
    return [self setObject: value forKey: aKey];
}

- (BOOL)setDate: (NSDate *)value forKey:(NSString *)aKey;
{
    return [self setObject: value forKey: aKey];
}

- (BOOL)setDictionary: (NSDictionary *)value forKey:(NSString *)aKey;
{
    return [self setObject: value forKey: aKey];
}

- (BOOL)setArray: (NSArray *)value forKey:(NSString *)aKey;
{
    return [self setObject: value forKey: aKey];
}

- (BOOL)removeObjectForKey: (NSString *)aKey;
{
    return [self removeDataItemForKey: NSDataFromString(aKey)];
}

#pragma mark - Getter Methods

- (BOOL)keyExists: (NSString *)key;
{
    return [self storedKeyExists: NSDataFromString(key)];
}

- (id)objectForKey: (NSString *)aKey;
{
    NSData *data = [self storedDataItemForKey: NSDataFromString(aKey)];
    return [self _objectFromPropertyListData: data];
}

- (NSArray *)arrayForKey: (NSString *)aKey;
{
    id result = [self objectForKey: aKey];
    if(result && [result isKindOfClass: [NSArray class]])
        return result;
    
    return nil;
}

- (NSDictionary *)dictionaryForKey: (NSString *)aKey;
{
    id result = [self objectForKey: aKey];
    if(result && [result isKindOfClass: [NSDictionary class]])
        return result;
    
    return nil;
}

- (NSString *)stringForKey: (NSString *)aKey;
{
    id result = [self objectForKey: aKey];
    if(result && [result isKindOfClass: [NSString class]])
        return result;
    
    return nil;
}

- (NSDate *)dateForKey: (NSString *)aKey;
{
    id result = [self objectForKey: aKey];
    if(result && [result isKindOfClass: [NSDate class]])
        return result;
    
    return nil;
}

- (NSData *)dataForKey: (NSString *)aKey;
{
    id result = [self objectForKey: aKey];
    if(result && [result isKindOfClass: [NSData class]])
        return result;
    
    return nil;
}



- (BOOL)boolForKey: (NSString *)aKey;
{
    id value = [self objectForKey: aKey];
    
    if(value && [value isKindOfClass: [NSNumber class]])
        return [value boolValue];
    
    return NO;
}

- (float)floatForKey: (NSString *)aKey;
{
    id value = [self objectForKey: aKey];
    
    if(value && [value isKindOfClass: [NSNumber class]])
        return [value floatValue];
    
    return 0;
}

- (NSInteger)integerForKey: (NSString *)aKey;
{
    id value = [self objectForKey: aKey];
    
    if(value && [value isKindOfClass: [NSNumber class]])
        return [value integerValue];
    
    return 0;
}

- (double)doubleForKey: (NSString *)aKey;
{
    id value = [self objectForKey: aKey];
    
    if(value && [value isKindOfClass: [NSNumber class]])
        return [value doubleValue];
    
    return 0;
}


#pragma mark - Enumeration

- (BOOL)enumerateKeysAndObjectsUsingBlock: (void (^) (id object, NSString *key, NSInteger count, BOOL *stop))block;
{
    return [self enumerateKeysAndObjectsStartWithKeyString: nil usingBlock: block];
}

- (BOOL)enumerateKeysAndObjectsStartWithKeyString: (NSString *)startKey usingBlock: (void (^) (id object, NSString *key, NSInteger count, BOOL *stop))block;
{
    return [self enumerateKeysAndDataItemsStartWithKey: startKey ? NSDataFromString(startKey) : nil
                                          usingBlock:^(NSData *data, NSData *key, NSInteger count, BOOL *stop) {
                                              block(data ? [self _objectFromPropertyListData: data] : nil, key ? NSStringFromData(key) : nil, count, stop);
                                          }];
}


- (BOOL)enumerateKeysUsingBlock: (void (^) (NSString *key, NSInteger count, BOOL *stop))block;
{
    return [self enumerateKeysStartWithKeyString: nil usingBlock: block];
}

- (BOOL)enumerateKeysStartWithKeyString: (NSString *)startKey usingBlock: (void (^) (NSString *key, NSInteger count, BOOL *stop))block;
{
    return [self enumarteKeysOnlyStartWithKey: startKey ? NSDataFromString(startKey) : nil
                                usingBlock:^(NSData *key, NSInteger count, BOOL *stop) {
                                    block(key ? NSStringFromData(key) : nil, count, stop);
                                }];
}


- (BOOL)enumerateObjectsUsingBlock: (void (^) (id object, NSInteger count, BOOL *stop))block;
{
    return [self enumerateObjectStartWithKeyString: nil usingBlock: block];
}

- (BOOL)enumerateObjectStartWithKeyString: (NSString *)startKey usingBlock: (void (^) (id object, NSInteger count, BOOL *stop))block;
{
    return [self enumerateDataItemsOnlyStartWithKey: startKey ? NSDataFromString(startKey) : nil
                                  usingBlock:^(NSData *data, NSInteger count, BOOL *stop) {
                                      block(data ? [self _objectFromPropertyListData: data] : nil, count, stop);
                                  }];
}




#pragma mark Sorted Set Handling
- (NSInteger)objectCountForKey: (NSString *)key;
{
    if(key)
        return [self dataItemsCountForKey: NSDataFromString(key)];
    
    return -1;
}

- (BOOL)addObject: (id)object forKey: (NSString *)aKey;
{
    NSData *data = [self _dataFromPropertyList: object];
    
    if(data && aKey)
    {
        return [self addDataItem: data toKey: NSDataFromString(aKey)];
    }
    
    return NO;
}

- (BOOL)replaceObjectForKey: (NSString *)aKey withObject: (id)object atIndex: (NSInteger)index;
{
    if(object && aKey && index >= 0)
    {
        return [self replaceDataItem: [self _dataFromPropertyList: object] forKey: NSDataFromString(aKey) atIndex: index];
    }
    
    return NO;
}

- (BOOL)replaceObject: (id)object withObject: (id)newObject forKey: (NSString *)aKey;
{
    if(object && newObject && aKey)
    {
        return [self replaceDataItem: [self _dataFromPropertyList: object] withDataItem: [self _dataFromPropertyList: newObject] forKey: NSDataFromString(aKey)];
    }
    
    return NO;
}

- (BOOL)removeObjectsForKey: (NSString *)aKey;
{
    return [self removeDataItemsForKey: NSDataFromString(aKey)];
}

- (BOOL)removeObject: (id)object forKey: (NSString *)aKey;
{
    return [self removeDataItem: [self _dataFromPropertyList: object] forKey: NSDataFromString(aKey)];
}

- (BOOL)removeObjectForKey: (NSString *)aKey atIndex: (NSInteger)index;
{
    return [self removeDataItemForKey: NSDataFromString(aKey) atIndex: index];
}

- (NSArray *)objectsForKey: (NSString *)aKey;
{
    __block NSMutableArray *result = [[NSMutableArray alloc] init];
    
    [self enumerateDataItemsForKey: NSDataFromString(aKey)
                       usingBlock:^(NSData *data, NSInteger index, BOOL *stop) {
                           if(data)
                               [result addObject: [self _objectFromPropertyListData: data]];
                       }];
    
    return result;
}

- (id)objectForKey: (NSString *)aKey atIndex: (NSInteger)index;
{
    NSData *data = [self dataItemForKey: NSDataFromString(aKey) atIndex: index];
    
    if(data)
    {
        return [self _objectFromPropertyListData: data];
    }
    
    return nil;
}

- (id)lastObjectForKey: (NSString *)aKey;
{
    NSData *data = [self lastDataItemForKey: NSDataFromString(aKey)];
    
    if(data)
    {
        return [self _objectFromPropertyListData: data];
    }
    
    return nil;
}

- (id)firstObjectForKey: (NSString *)aKey;
{
    NSData *data = [self firstDataItemForKey: NSDataFromString(aKey)];
    
    if(data)
    {
        return [self _objectFromPropertyListData: data];
    }
    
    return nil;
}

- (BOOL)enumerateObjectsForKey: (NSString *)key usingBlock: (void (^) (id object, NSInteger index, BOOL *stop))block;
{
    return [self enumerateDataItemsForKey: NSDataFromString(key)
                              usingBlock:^(NSData *data, NSInteger index, BOOL *stop) {
                                  block(data ? [self _objectFromPropertyListData: data] : nil, index, stop);
                              }];
}

@end
