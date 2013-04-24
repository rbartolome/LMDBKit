//
//  LMDBKit.h
//
//  Created by Raphael Bartolome on 18.04.13.
//  Copyright (c) 2013 Raphael Bartolome. All rights reserved.
//

#import <Foundation/Foundation.h>

#define NSDataFromString(aString) [aString dataUsingEncoding: NSUTF8StringEncoding]
#define NSStringFromData(data) [NSString stringWithUTF8String: [data bytes]]

@class LMDBTransaction, LMDBI;

extern NSString *const LMDBKitErrorDomain;

enum {
    LMDBKitErrorCodeUnknown = 0,
    LMDBKitErrorCodeDatabaseFull,
    LMDBKitErrorCodeTransactionFull,
    LMDBKitErrorCodeTransactionCommitFailedError,
    LMDBKitErrorCodeAttemptToWriteInReadOnlyTransaction
};
typedef NSInteger LMDBKitErrorCode;


#pragma mark - Environment
@interface LMDBEnvironment : NSObject

- (id)initWithPath: (NSString *)path startImmediately: (BOOL)start;

#pragma mark Environment Handling
- (BOOL)openEnvironment;
- (BOOL)openEnvironmentWithMapSize: (int)size;
- (BOOL)openEnvironmentWithMapSize: (int)size maximumNumberOfDatabases: (int)maximumNumber;

- (BOOL)copyEnvironmentToPath: (NSString *)path;
- (void)closeEnvironment;

#pragma mark Database Handling
- (BOOL)openDatabaseNamed: (NSString *)name;
- (BOOL)openDatabaseNamed: (NSString *)name allowDuplicatedKeys: (BOOL)duplicatedKeys;

- (BOOL)dropDatabaseNamed: (NSString *)name;
- (BOOL)dropDatabaseNamed: (NSString *)name parentTransaction: (LMDBTransaction *)trans;

#pragma mark Manual Transaction Handling
- (LMDBTransaction *)beginTransaction;
- (LMDBTransaction *)beginTransactionWithParent: (LMDBTransaction *)parent readonly: (BOOL)readonly;

- (BOOL)commitTransaction: (LMDBTransaction *)transaction error: (NSError **)error;
- (void)abortTransaction: (LMDBTransaction *)transaction;

#pragma mark Background Transaction Handling
/** @brief Creates a serial and writable Transaction.
 *
 * @param A block which gets called async
 * @param completion block that might contain a error if the transaction failed to commit otherwise cleanup here
 */
- (void)transaction: (void (^) (LMDBTransaction *txn, BOOL *rollback))block completion: (void (^) (NSError *error))completion;

/** @brief Creates a Transaction.
 *
 * A readonly transaction will be called concurrent while a writable transaction gets called in a serial way
 * @param readonly option
 * @param completion block that might contain a error if the transaction failed to commit otherwise cleanup here
 * @param A block which gets called async
 */
- (void)transaction: (BOOL)readonly usingBlock: (void (^) (LMDBTransaction *txn, BOOL *rollback))block completion: (void (^) (NSError *error))completion;

/** @brief Creates a Transaction.
 *
 * A readonly transaction will be called concurrent while a writable transaction gets called in a serial way
 * @param a parent transaction. If a parent transaction is readonly the nested transaction will be readonly too
 * @param readonly option
 * @param A block which gets called async
 * @param completion block that might contain a error if the transaction failed to commit otherwise cleanup here
 */
- (void)transactionWithParent: (LMDBTransaction *)parent readonly: (BOOL)readonly usingBlock: (void (^) (LMDBTransaction *txn, BOOL *rollback))block completion: (void (^) (NSError *error))completion;

/** @brief Shows all active async transaction.
 *
 * @return The count of active async transactions
 */
- (NSInteger)activeTransactions;

@end


#pragma mark - Transaction
@interface LMDBTransaction : NSObject

- (id)initWithEnvironment: (LMDBEnvironment *)environment readonly: (BOOL)readonly parent: (LMDBTransaction *)parent;

- (BOOL)readonly;
- (LMDBEnvironment *)environment;

/** @brief Returns a error
 *
 * It returns transaction and database related errors. If after you write to a database the error will find here
 * @return nil if no error occures
 */
- (NSError *)error;
- (void)resetError;

/** @brief Returns the default database named __default__.
 *
 * The default database will create on environment startup
 * @return The LMBDI Proxy database instance __default__
 */
- (LMDBI *)db;

/** @brief Returns a databse with given name
 *
 * if the transaction isn't readonly and the database didn't exists it will created
 * @param The database name
 * @return a LMBDI Proxy database instance
 */
- (LMDBI *)db: (NSString *)name;

@end

#pragma mark - Database
@interface LMDBI : NSProxy

#pragma mark Default Key/Value Handling
- (NSInteger)count;
- (BOOL)exists: (NSData *)key;

- (BOOL)set: (NSData *)data key: (NSData *)key;
- (NSData *)get: (NSData *)key;
- (BOOL)del: (NSData *)key;

- (BOOL)enumerateKeysAndObjectsUsingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateKeysAndObjectsStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;

- (BOOL)enumerateKeysUsingBlock: (void (^) (NSData *key, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateKeysStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *key, NSInteger count, BOOL *stop))block;

- (BOOL)enumerateObjectsUsingBlock: (void (^) (NSData *data, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateObjectStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *data, NSInteger count, BOOL *stop))block;


#pragma mark Sorted Set Handling
- (NSInteger)scount: (NSData *)key;

- (BOOL)sadd: (NSData *)data key: (NSData *)key;

- (BOOL)srep: (NSData *)data key: (NSData *)key atIndex: (NSInteger)index;
- (BOOL)srep: (NSData *)data withData: (NSData *)newData key: (NSData *)key;

- (BOOL)sdel: (NSData *)key;
- (BOOL)sdel: (NSData *)key data: (NSData *)data;
- (BOOL)sdel: (NSData *)key atIndex: (NSInteger)index;

- (NSArray *)sget: (NSData *)key;
- (NSData *)sget: (NSData *)key atIndex: (NSInteger)index;
- (NSData *)sgetlast: (NSData *)key;
- (NSData *)sgetfirst: (NSData *)key;

- (BOOL)senumerateObjectsForKey: (NSData *)key usingBlock: (void (^) (NSData *data, NSInteger index, BOOL *stop))block;

@end
