//
//  LMDBKit.h
//
//  Created by Raphael Bartolome on 18.04.13.
//  Copyright (c) 2013 Raphael Bartolome. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LMDBTransaction, LMDBI;

#define NSDataFromString(aString) aString ? [aString dataUsingEncoding: NSUTF8StringEncoding] : nil
#define NSStringFromData(data) data ? [NSString stringWithUTF8String: [data bytes]] : nil

/** @brief This Notification will post to the default center after write to a database will fail because of the database size or transaction size is to small
 *
 * The userInfo dictionary of the notification contains the key kLMDBKitEnvironmentKey, kLMDBKitDatabaseNameKey and kLMDBKitErrorKey which contains the error with a LMDBKitErrorCode.
 * This might be the same error you will get from a transaction after you've commit it.
 */

extern NSString *const LMDBDatabaseReachSizeLimitNotification;

/** @brief This Notification will post to the default center after a writable Transaction has commit with changes
 *
 * The userInfo dictionary of the notification contains the key kLMDBKitEnvironmentKey which value is the environment and kLMDBKitDatabaseNamesKey which value is the databases name used in the transaction.
 */
extern NSString *const LMDBTransactionDidCommitUpdatesNotification;

extern NSString *const kLMDBKitEnvironmentKey;
extern NSString *const kLMDBKitDatabaseNameKey;
extern NSString *const kLMDBKitErrorKey;
extern NSString *const kLMDBKitDatabaseNamesKey;

extern NSString *const kLMDBKitDefaultDatabaseName;
extern NSString *const kLMDBKitErrorDomain;

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

/** @brief Creates a environment at path.
 *
 * The environment file will be created beside a lock file at the given path.
 * @param path to enviroment is a directory, otherwise it will be created.
 * @param if NO, you have to open the enviroment manually otherwise it will create with a max db size of 1024 MB and 32 databases.
 */
- (id)initWithPath: (NSString *)path startImmediately: (BOOL)start;

#pragma mark Environment Handling
- (BOOL)openEnvironment;
- (BOOL)openEnvironmentWithMaxMapSize: (int)size;
- (BOOL)openEnvironmentWithMaxMapSize: (int)size maximumNumberOfDatabases: (int)maximumNumber;

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
 * @param completion block that might contain a error if the transaction failed to commit otherwise cleanup here.
 */
- (void)transaction: (void (^) (LMDBTransaction *txn, BOOL *rollback))block completion: (void (^) (NSError *error))completion;

/** @brief Creates a Transaction.
 *
 * A readonly transaction will be called concurrent while a writable transaction gets called in a serial way
 * @param readonly option
 * @param completion block that might contain a error if the transaction failed to commit otherwise cleanup here.
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
- (LMDBI *)dbi;

/** @brief Returns a databse with given name
 *
 * if the transaction isn't readonly and the database didn't exists it will created
 * @param The database name
 * @return a LMBDI Proxy database instance
 */
- (LMDBI *)dbi: (NSString *)name;

@end

#pragma mark - Database
@interface LMDBI : NSProxy

- (BOOL)isFull;

#pragma mark Default Key/Value Handling
- (NSInteger)keysCount;
- (BOOL)storedKeyExists: (NSData *)key;

- (BOOL)storeDataItem: (NSData *)data forKey: (NSData *)key;
- (NSData *)storedDataItemForKey: (NSData *)key;
- (BOOL)removeDataItemForKey: (NSData *)key;

- (BOOL)enumerateKeysAndDataItemsUsingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateKeysAndDataItemsStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;

- (BOOL)enumerateKeysOnlyUsingBlock: (void (^) (NSData *key, NSInteger count, BOOL *stop))block;
- (BOOL)enumarteKeysOnlyStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *key, NSInteger count, BOOL *stop))block;

- (BOOL)enumerateDataItemsOnlyUsingBlock: (void (^) (NSData *data, NSInteger count, BOOL *stop))block;
- (BOOL)enumerateDataItemsOnlyStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *data, NSInteger count, BOOL *stop))block;


#pragma mark Sorted Set Handling
- (NSInteger)dataItemsCountForKey: (NSData *)key;

- (BOOL)addDataItem: (NSData *)data toKey: (NSData *)key;

- (BOOL)replaceDataItem: (NSData *)data forKey: (NSData *)key atIndex: (NSInteger)index;
- (BOOL)replaceDataItem: (NSData *)data withDataItem: (NSData *)newData forKey: (NSData *)key;

- (BOOL)removeDataItemsForKey: (NSData *)key;
- (BOOL)removeDataItem: (NSData *)data forKey: (NSData *)key;
- (BOOL)removeDataItemForKey: (NSData *)key atIndex: (NSInteger)index;

- (NSArray *)dataItemsForKey: (NSData *)key;
- (NSData *)dataItemForKey: (NSData *)key atIndex: (NSInteger)index;
- (NSData *)lastDataItemForKey: (NSData *)key;
- (NSData *)firstDataItemForKey: (NSData *)key;

- (BOOL)enumerateDataItemsForKey: (NSData *)key usingBlock: (void (^) (NSData *data, NSInteger index, BOOL *stop))block;

@end
