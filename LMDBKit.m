//
//  LMDBKit.m
//
//  Created by Raphael Bartolome on 18.04.13.
//  Copyright (c) 2013 Raphael Bartolome. All rights reserved.
//

#import "LMDBKit.h"
#import "lmdb.h"


NSString *const kLMDBKitDefaultDatabaseName = @"__default__";

NSString *const kLMDBKitErrorDomain = @"lmdb.kit.error";

NSString *const LMDBDatabaseReachSizeLimitNotification = @"LMDBDatabaseReachSizeLimitNotification";

NSString *const LMDBTransactionDidCommitUpdatesNotification = @"LMDBTransactionDidCommitUpdatesNotification";

NSString *const kLMDBKitEnvironmentKey = @"kLMDBKitEnvironmentKey";
NSString *const kLMDBKitDatabaseNameKey = @"kLMDBKitDatabaseNameKey";
NSString *const kLMDBKitErrorKey = @"kLMDBKitErrorKey";
NSString *const kLMDBKitDatabaseNamesKey = @"kLMDBKitDatabasesNameKey";

#pragma mark - Private Interfaces

@interface _LMDBI : NSObject

- (id)initDBIWithName: (NSString *)name allowDuplicatedKeys: (BOOL)dup transaction: (LMDBTransaction *)transaction;
- (void)close: (LMDBEnvironment *)manager;
- (void)drop: (LMDBTransaction *)txn;

- (BOOL)allowDuplicatedKeys;

- (MDB_dbi)dbi;

@end

@interface LMDBI ()

+ (id)dbWithTransaction: (LMDBTransaction *)txn original: (_LMDBI *)db;
- (id)initWithTransaction: (LMDBTransaction *)txn original: (_LMDBI *)db;


@end

@interface LMDBTransaction ()
{

}

- (void)_markChanges: (NSString *)dbName;

- (MDB_txn *)txn;

- (int)commit;
- (void)abort;

- (void)reset;
- (int)renew;

@end


@interface LMDBEnvironment ()
{
    
}

- (MDB_env *)env;

- (_LMDBI *)databaseNamed: (NSString *)name create: (BOOL)create allowDuplicatedKeys: (BOOL)duplicates parentTransaction: (LMDBTransaction *)trans created: (BOOL *)created;

- (void)closeDatabaseNamed: (NSString *)name;

@end


#pragma mark - LMDB Environment Implementation
@implementation LMDBEnvironment
{
    NSString *_path;
    MDB_env *_mdb_env;

    dispatch_queue_t _processQueue;
    
    dispatch_queue_t _databasesAccessQueue;
    NSMutableDictionary *_databases;
    
    dispatch_queue_t _activeTransactionQueue;
    NSInteger _activeTransactions;
}

- (void)dealloc;
{
    [self closeEnvironment];
    _path = nil;
}

- (MDB_env *)env;
{
    return _mdb_env;
}


- (id)initWithPath: (NSString *)path startImmediately: (BOOL)start;
{
    if((self = [super init]))
    {
        _path = [path copy];
        _mdb_env = NULL;
        _processQueue = dispatch_queue_create([[@"lmdb.process.%@" stringByAppendingString: path] UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _databasesAccessQueue = dispatch_queue_create([[@"lmdb.dbs.%@" stringByAppendingString: path] UTF8String], DISPATCH_QUEUE_SERIAL);
        _databases = [[NSMutableDictionary alloc] init];
        
        _activeTransactionQueue = dispatch_queue_create([[@"lmdb.atq.%@" stringByAppendingString: path] UTF8String], DISPATCH_QUEUE_SERIAL);
        _activeTransactions = 0;
        
        [[NSFileManager defaultManager] createDirectoryAtPath: _path
                                  withIntermediateDirectories: YES
                                                   attributes: nil error: nil];
        
        if(start)
        {
            [self openEnvironment];
        }
    }
    
    return self;
}

#pragma mark Environment

- (BOOL)openEnvironment;
{
    return [self openEnvironmentWithMaxMapSize: 1024 maximumNumberOfDatabases: 32];
}

- (BOOL)openEnvironmentWithMaxMapSize: (int)size;
{
    return [self openEnvironmentWithMaxMapSize: size maximumNumberOfDatabases: 32];
}

- (BOOL)openEnvironmentWithMaxMapSize: (int)size maximumNumberOfDatabases: (int)maximumNumber;
{
    BOOL result = YES;
    if(!_mdb_env)
    {
        int rc;
        rc = mdb_env_create(&_mdb_env);
        rc = mdb_env_set_mapsize(_mdb_env, size*1024*1024);
        rc = mdb_env_set_maxdbs(_mdb_env, maximumNumber);
        rc = mdb_env_open(_mdb_env, [_path UTF8String], 0, 0660);
        
        BOOL created = NO;
        [self databaseNamed: kLMDBKitDefaultDatabaseName create: YES allowDuplicatedKeys: YES parentTransaction: nil created: &created];
        
        result = rc ? NO : YES;
    }
    
    return result;
}

- (BOOL)copyEnvironmentToPath: (NSString *)path;
{
    BOOL result = YES;
    
    dispatch_sync(_processQueue, ^{
        [[NSFileManager defaultManager] createDirectoryAtPath: path
                                  withIntermediateDirectories: YES
                                                   attributes: nil error: nil];
        
        mdb_env_copy(_mdb_env, [path UTF8String]);
    });
    
    return result;
}

- (void)closeEnvironment;
{
    if(_mdb_env)
    {
        dispatch_sync(_processQueue, ^() {
            [self closeDatabaseNamed: kLMDBKitDefaultDatabaseName];
            
            NSArray *_names = [_databases allKeys];
            [_names enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                [self closeDatabaseNamed: obj];
            }];
            
            mdb_env_close(_mdb_env);
            _mdb_env = NULL;
        });
    }
}



#pragma mark Database instances

- (BOOL)openDatabaseNamed: (NSString *)name;
{
    return [self openDatabaseNamed: name allowDuplicatedKeys: YES];
}

- (BOOL)openDatabaseNamed: (NSString *)name allowDuplicatedKeys: (BOOL)duplicatedKeys;
{
    BOOL created = NO;    
    return [self databaseNamed: name create: YES allowDuplicatedKeys: duplicatedKeys parentTransaction: nil created: &created] ? YES : NO;
}

- (_LMDBI *)databaseNamed: (NSString *)name create: (BOOL)create allowDuplicatedKeys: (BOOL)dup parentTransaction: (LMDBTransaction *)trans created: (BOOL *)created;
{
    __block _LMDBI *lmdbi = nil;
    
    dispatch_sync(_databasesAccessQueue, ^{
        NSString *_name = kLMDBKitDefaultDatabaseName;
        
        if(name)
            _name = name;
        
        lmdbi = [_databases objectForKey: _name];
        
        if(!lmdbi && create)
        {
            *created = YES;
            lmdbi = [self _openDatabaseNamed: _name allowDuplicatedKeys: dup parent: trans];
            if(lmdbi)
                [_databases setObject: lmdbi forKey: _name];
        }
    });

    return lmdbi;
}

- (void)closeDatabaseNamed: (NSString *)name;
{
    dispatch_sync(_databasesAccessQueue, ^{
        
        NSString *_name = kLMDBKitDefaultDatabaseName;
        
        if(name)
            _name = name;
        
        _LMDBI *lmdbi = [_databases objectForKey: _name];
        if(lmdbi)
        {
            [lmdbi close: self];
            lmdbi = nil;
            
            [_databases removeObjectForKey: _name];
        }
    });
}

- (BOOL)dropDatabaseNamed: (NSString *)name;
{
    return [self dropDatabaseNamed: name parentTransaction: nil];
}

- (BOOL)dropDatabaseNamed: (NSString *)name parentTransaction: (LMDBTransaction *)trans;
{
    __block BOOL result = YES;
    dispatch_sync(_databasesAccessQueue, ^{
        NSString *_name = kLMDBKitDefaultDatabaseName;
        
        if(name)
            _name = name;
        
        _LMDBI *lmdbi = [_databases objectForKey: _name];
        if(!lmdbi)
        {
            lmdbi = [self _openDatabaseNamed: _name allowDuplicatedKeys: YES parent: trans];
        }

        LMDBTransaction *txn = [self beginTransactionWithParent: trans readonly: NO];

        [lmdbi drop: txn];
        lmdbi = nil;
        
        [_databases removeObjectForKey: _name];

        result = [self commitTransaction: txn error: nil];
    });
    
    return result;
}


- (_LMDBI *)_openDatabaseNamed: (NSString *)name allowDuplicatedKeys: (BOOL)dup parent: (LMDBTransaction *)trans;
{
    NSString *_name = kLMDBKitDefaultDatabaseName;
    
    if(name)
        _name = name;
    
    BOOL result = YES;
    LMDBTransaction *txn = [self beginTransactionWithParent: trans readonly: NO];
    
    _LMDBI *dbi = [[_LMDBI alloc] initDBIWithName: _name allowDuplicatedKeys: dup transaction: txn];
    
    if(dbi)
    {
        result = [self commitTransaction: txn error: nil];
    }
    else
    {
        [self abortTransaction: txn];
        result = NO;
    }
    
    if(!result)
        dbi = nil;
    
    return dbi;
}


#pragma mark Transactions

- (LMDBTransaction *)beginTransaction;
{
    return [self beginTransactionWithParent: nil readonly: NO];
}


- (LMDBTransaction *)beginTransactionWithParent: (LMDBTransaction *)parent readonly: (BOOL)readonly;
{
    LMDBTransaction *_transaction = [[LMDBTransaction alloc] initWithEnvironment: self readonly: readonly parent: parent];
    return _transaction;
}

- (BOOL)commitTransaction: (LMDBTransaction *)transaction error: (NSError **)error;
{
    int rc = 0;
    if([transaction readonly])
    {
        [transaction abort];
    }
    else
    {
        rc = [transaction commit];
        
        if(rc != 0 && error)
        {
            *error = [transaction error];
        }
    }
    
    transaction = nil;
    
    return rc ? NO : YES;
}

- (void)abortTransaction: (LMDBTransaction *)transaction;
{
    [transaction abort];
    transaction = nil;
}

- (NSInteger)activeTransactions;
{
    __block NSInteger result = 0;
    dispatch_sync(_activeTransactionQueue, ^{
        result = _activeTransactions;
    });
    return result;
}

- (void)incrActiveTransactions;
{
    dispatch_async(_activeTransactionQueue, ^{
        _activeTransactions = _activeTransactions + 1;
    });
}

- (void)decrActiveTransactions;
{
    dispatch_async(_activeTransactionQueue, ^{
        _activeTransactions = _activeTransactions - 1;
    });
}

- (void)transaction: (void (^) (LMDBTransaction *txn, BOOL *rollback))block completion: (void (^) (NSError *error))completion;
{
    [self transactionWithParent: nil readonly: NO usingBlock: block completion: completion];
}

- (void)transaction: (BOOL)readonly usingBlock: (void (^) (LMDBTransaction *txn, BOOL *rollback))block completion: (void (^) (NSError *error))completion;
{
    [self transactionWithParent: nil readonly: readonly usingBlock: block completion: completion];
}

- (void)transactionWithParent: (LMDBTransaction *)parent readonly: (BOOL)readonly usingBlock: (void (^) (LMDBTransaction *txn, BOOL *rollback))block completion: (void (^) (NSError *error))completion;
{
    [self incrActiveTransactions];
    dispatch_async(_processQueue, ^{
        LMDBTransaction *trans = [self beginTransactionWithParent: parent readonly: readonly];
        
        BOOL roll = NO;
        
        block(trans, &roll);
        
        if(roll || readonly)
        {
            [self abortTransaction: trans];
            completion(nil);
        }
        else
        {
            NSError *error = nil;
            BOOL result = [self commitTransaction: trans error: &error];
            
            if(!result)
            {
                completion(error);
            }
            else
            {
                completion(nil);
            }
        }
        
        trans = nil;
        [self decrActiveTransactions];
    });
}

@end



#pragma mark - Transaction Implementation
@implementation LMDBTransaction
{
    LMDBEnvironment *_env;
    BOOL _readonly;
    MDB_txn *_txn;
    NSError *_txn_error;
    
    NSMutableSet *_databasesChanged;
}

- (void)dealloc;
{
    if(_txn && _env)
    {
        if(_readonly)
            [self abort];
        else
            [self commit];
    }
    
    _txn_error = nil;
    _env = nil;
    _databasesChanged = nil;
}

- (void)_markChanges: (NSString *)dbName;
{
    if(!_databasesChanged)
        _databasesChanged = [[NSMutableSet alloc] init];
    
    [_databasesChanged addObject: dbName];
}

- (id)initWithEnvironment: (LMDBEnvironment *)environment readonly: (BOOL)readonly parent: (LMDBTransaction *)parent;
{
    if((self = [super init]))
    {
        if([parent readonly] && !readonly)
            _readonly = YES;
        else
            _readonly = readonly;
        
        _env = environment;
        int rc = mdb_txn_begin([environment env], parent ? [parent txn] : NULL, _readonly ? MDB_RDONLY : 0, &_txn);
        
        if(rc)
        {
            return nil;
        }
        
        _databasesChanged = [[NSMutableSet alloc] init];
    }
    
    return self;
}

- (NSError *)error;
{
    return _txn_error;
}

- (void)resetError;
{
    [self setError: nil];
}

- (void)setError: (NSError *)error;
{
    _txn_error = error;
}

- (LMDBI *)dbi;
{
    return [self dbi: nil];
}

- (LMDBI *)dbi: (NSString *)name;
{
    BOOL created = NO;
    _LMDBI *dbi = [_env databaseNamed: name create: !_readonly allowDuplicatedKeys: YES parentTransaction: self created: &created];
    if(!dbi)
        return nil;
    
    return [LMDBI dbWithTransaction: self original: dbi];
}

- (BOOL)readonly;
{
    return _readonly;
}

- (LMDBEnvironment *)environment;
{
    return _env;
}

- (MDB_txn *)txn;
{
    return _txn;
}

- (int)commit;
{
    int rc = mdb_txn_commit([self txn]);
    _txn = NULL;
    
    if(rc)
    {
        if(_txn_error)
        {
            NSDictionary *userInfo = [_txn_error userInfo];
            [self setError: [NSError errorWithDomain: kLMDBKitErrorDomain
                                                code: LMDBKitErrorCodeTransactionCommitFailedError
                                            userInfo: userInfo]];
        }
        else
        {
            [self setError: [NSError errorWithDomain: kLMDBKitErrorDomain
                                                code: LMDBKitErrorCodeTransactionCommitFailedError
                                            userInfo: @{NSLocalizedDescriptionKey: @"Transaction commit failed and did abort"}]];
        }
    }
    else
    {
        if(_databasesChanged && [_databasesChanged count])
            [[NSNotificationCenter defaultCenter] postNotificationName: LMDBTransactionDidCommitUpdatesNotification
                                                                object: self
                                                              userInfo: @{kLMDBKitEnvironmentKey: _env, kLMDBKitDatabaseNamesKey: _databasesChanged}];
    }
    
    return rc;
}

- (void)abort;
{
    mdb_txn_abort([self txn]);
    _txn = NULL;
    
    _databasesChanged = nil;
}

- (void)reset;
{
    mdb_txn_reset([self txn]);
    
    _databasesChanged = nil;
}

- (int)renew;
{
    int rc = mdb_txn_renew([self txn]);
    return rc;
}

@end


#pragma mark - Database Instance Implemenation

@implementation _LMDBI
{
    NSString *_name;
    BOOL _allowDuplicatedKeys;
    MDB_dbi _dbi;
}

- (instancetype)initDBIWithName: (NSString *)name allowDuplicatedKeys: (BOOL)dup transaction: (LMDBTransaction *)transaction;
{
    if((self = [super init]))
    {
        _name = name;
        _allowDuplicatedKeys = dup;
        int rc;
        if(_allowDuplicatedKeys)
            rc = mdb_dbi_open([transaction txn], [name UTF8String], MDB_CREATE|MDB_DUPSORT, &_dbi);
        else
            rc = mdb_dbi_open([transaction txn], [name UTF8String], MDB_CREATE, &_dbi);
        
        if(rc)
        {
            self = nil;
        }
    }
    
    return self;
}

- (void)dealloc;
{
    _name = nil;
}

- (NSString *)name;
{
    return _name;
}

- (BOOL)allowDuplicatedKeys;
{
    return _allowDuplicatedKeys;
}

- (MDB_dbi)dbi;
{
    return _dbi;
}

- (void)close: (LMDBEnvironment *)manager;
{
    mdb_dbi_close([manager env], [self dbi]);
}

- (void)drop: (LMDBTransaction *)txn;
{
    mdb_drop([txn txn], [self dbi], 1);
    
}

@end


@implementation LMDBI
{
    __weak _LMDBI *_original;
    __weak LMDBTransaction *_txn;
}

- (void)dealloc
{
    _original = nil;
    _txn = nil;
}

+ (instancetype)dbWithTransaction: (LMDBTransaction *)txn original: (_LMDBI *)db;
{
    return [[[self class] alloc] initWithTransaction: txn original: db];
}

- (instancetype)initWithTransaction: (LMDBTransaction *)txn original: (_LMDBI *)db;
{
    _original = db;
    _txn = txn;
    
    if(!_original)
        return nil;
    
    return self;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    if (_original != nil) {
        [invocation setTarget: _original];
        [invocation invoke];
    }
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    NSMethodSignature *result;
    if (_original != nil)
    {
        result = [_original methodSignatureForSelector:sel];
    }
    else
    {
        //Will throw an exception as default implementation
        result = [super methodSignatureForSelector:sel];
    }
    
    return result;
}

- (BOOL)isFull;
{
    MDB_stat stat;
    mdb_stat([_txn txn], [_original dbi], &stat);
    MDB_envinfo info;
    mdb_env_info([[_txn environment] env], &info);
    
    size_t max_pgno = info.me_mapsize/stat.ms_psize;
    size_t last_pgno = info.me_last_pgno;
    NSLog(@"%zi - %zi", last_pgno, max_pgno);
    
    return last_pgno < max_pgno ? NO : YES;
}

#pragma mark Single Values Operations

- (NSInteger)keysCount;
{
    MDB_stat stat;
    NSInteger count = 0;
    MDB_cursor *cursor;
    
    if(mdb_cursor_open([_txn txn], [_original dbi], &cursor) == 0)
        mdb_cursor_close(cursor);
    
    int rc = mdb_stat([_txn txn], [_original dbi], &stat);
    
    if(rc == 0)
    {
        count = stat.ms_entries;
    }
    
    return count;
}

- (BOOL)storedKeyExists: (NSData *)key;
{
    MDB_val _key;
    MDB_val _data;
    
    _key.mv_size = [key length];
    _key.mv_data = (void *)[key bytes];
    
    int rc = mdb_get([_txn txn], [_original dbi], &_key, &_data);

    return rc ? NO : YES;
}

- (BOOL)storeDataItem: (NSData *)data forKey: (NSData *)key;
{
    BOOL result = NO;
    int rc = 0;

    if(data)
    {
        MDB_val _key;
        MDB_val _data;

        _key.mv_size = [key length];
        _key.mv_data = (void *)[key bytes];

        _data.mv_size = [data length];
        _data.mv_data = (void *)[data bytes];

        if([_original allowDuplicatedKeys])
        {
            [self removeDataItem: key forKey: nil];
        }

        rc = mdb_put([_txn txn], [_original dbi], &_key, &_data, 0);
        
        if(rc != 0)
        {
            switch (rc)
            {
                case MDB_MAP_FULL:
                {
                    NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                          code: LMDBKitErrorCodeDatabaseFull
                                                      userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                    [_txn setError: aError];
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName: LMDBDatabaseReachSizeLimitNotification
                                                                        object: self
                                                                      userInfo: @{kLMDBKitErrorKey: [_txn error], kLMDBKitEnvironmentKey: [_txn environment], kLMDBKitDatabaseNameKey: [_original name]}];
                    break;
                }
                case MDB_TXN_FULL:
                {
                    NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                          code: LMDBKitErrorCodeDatabaseFull
                                                      userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                    [_txn setError: aError];
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName: LMDBDatabaseReachSizeLimitNotification
                                                                        object: self
                                                                      userInfo: @{kLMDBKitErrorKey: [_txn error], kLMDBKitEnvironmentKey: [_txn environment], kLMDBKitDatabaseNameKey: [_original name]}];
                    break;
                }
                case EACCES:
                {
                    NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                          code: LMDBKitErrorCodeAttemptToWriteInReadOnlyTransaction
                                                      userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                    [_txn setError: aError];
                    break;
                }
                default:
                    break;
            }
        }
    }

    result = rc ? NO : YES;
    
    if(result)
        [_txn _markChanges: [_original name]];

    return result;
}


- (NSData *)storedDataItemForKey: (NSData *)key;
{
    MDB_val _key;
    MDB_val _data;

    _key.mv_size = [key length];
    _key.mv_data = (void *)[key bytes];

    int rc = mdb_get([_txn txn], [_original dbi], &_key, &_data);

    if(rc == MDB_NOTFOUND)
        return nil;

    return [NSData dataWithBytes: _data.mv_data length: _data.mv_size];
}

- (BOOL)removeDataItemForKey: (NSData *)key;
{
    [_txn _markChanges: [_original name]];
    return [self removeDataItem: key forKey: nil];
}

#pragma mark Duplicate Values Operations

- (BOOL)addDataItem: (NSData *)data toKey: (NSData *)key;
{
    BOOL result = NO;
    int rc = 0;

    if(data)
    {
        MDB_val _key;
        MDB_val _data;

        _key.mv_size = [key length];
        _key.mv_data = (void *)[key bytes];

        _data.mv_size = [data length];
        _data.mv_data = (void *)[data bytes];

        rc = mdb_put([_txn txn], [_original dbi], &_key, &_data, 0);
        
        if(rc != 0)
        {
            switch (rc)
            {
                case MDB_MAP_FULL:
                {
                    NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                          code: LMDBKitErrorCodeDatabaseFull
                                                      userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                    [_txn setError: aError];
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName: LMDBDatabaseReachSizeLimitNotification
                                                                        object: self
                                                                      userInfo: @{kLMDBKitErrorKey: [_txn error], kLMDBKitEnvironmentKey: [_txn environment], kLMDBKitDatabaseNameKey: [_original name]}];
                    break;
                }
                case MDB_TXN_FULL:
                {
                    NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                          code: LMDBKitErrorCodeDatabaseFull
                                                      userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                    [_txn setError: aError];
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName: LMDBDatabaseReachSizeLimitNotification
                                                                        object: self
                                                                      userInfo: @{kLMDBKitErrorKey: [_txn error], kLMDBKitEnvironmentKey: [_txn environment], kLMDBKitDatabaseNameKey: [_original name]}];
                    break;
                }
                case EACCES:
                {
                    NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                          code: LMDBKitErrorCodeAttemptToWriteInReadOnlyTransaction
                                                      userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                    [_txn setError: aError];
                    break;
                }
                default:
                    break;
            }
        }
    }

    result = rc ? NO : YES;
    
    if(result)
        [_txn _markChanges: [_original name]];
    
    return result;
}

- (BOOL)replaceDataItem: (NSData *)data forKey: (NSData *)key atIndex: (NSInteger)index;
{
    BOOL result = [self removeDataItemForKey: key atIndex: index];

    if(result)
    {
        result = [self addDataItem: data toKey: key];
        
        if(result)
            [_txn _markChanges: [_original name]];
    }

    return result;
}

- (BOOL)replaceDataItem: (NSData *)data withDataItem: (NSData *)newData forKey: (NSData *)key;
{
    BOOL result = [self removeDataItem: key forKey: data];
    if(result)
    {
        result = [self addDataItem: newData toKey: key];
        
        if(result)
            [_txn _markChanges: [_original name]];
    }

    return result;
}

- (BOOL)removeDataItemsForKey: (NSData *)key;
{
    return [self removeDataItem: key forKey: nil];
}

- (BOOL)removeDataItem: (NSData *)data forKey: (NSData *)key;
{
    BOOL result = NO;
    MDB_val _key;
    MDB_val _data;

    _key.mv_size = [key length];
    _key.mv_data = (void *)[key bytes];

    if(data)
    {
        _data.mv_size = [data length];
        _data.mv_data = (void *)[data bytes];
    }

    int rc = mdb_del([_txn txn], [_original dbi], &_key, data ? &_data : NULL);

    if(rc != 0)
    {
        switch (rc)
        {
            case EACCES:
            {
                NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                      code: LMDBKitErrorCodeAttemptToWriteInReadOnlyTransaction
                                                  userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                [_txn setError: aError];
                break;
            }
            default:
                break;
        }
    }
    
    result = rc ? NO : YES;

    if(result)
        [_txn _markChanges: [_original name]];

    return result;
}

- (BOOL)removeDataItemForKey: (NSData *)key atIndex: (NSInteger)index;
{
    BOOL result = NO;
    if([_original allowDuplicatedKeys])
    {
        MDB_cursor *cursor;
        MDB_val _key, _data;

        _key.mv_size = [key length];
        _key.mv_data = (void *)[key bytes];

        int rc = mdb_cursor_open([_txn txn], [_original dbi], &cursor);

        if(rc == 0)
        {
            rc = mdb_cursor_get(cursor, &_key, &_data, MDB_SET_KEY);

            if(rc == 0)
            {
                NSInteger lindex = 0;
                result = YES;

                do
                {
                    if(lindex == index)
                    {
                        rc = mdb_cursor_del(cursor, 0);
                        break;
                    }
                    lindex++;
                } while ((rc = mdb_cursor_get(cursor, &_key, &_data, MDB_NEXT_DUP)) == 0);
            }

            mdb_cursor_close(cursor);
        }
        
        if(rc != 0)
        {
            switch (rc)
            {
                case EACCES:
                {
                    NSError *aError = [NSError errorWithDomain: kLMDBKitErrorDomain
                                                          code: LMDBKitErrorCodeAttemptToWriteInReadOnlyTransaction
                                                      userInfo: [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"%s", mdb_strerror(rc)] forKey: NSLocalizedDescriptionKey]];
                    [_txn setError: aError];
                    break;
                }
                default:
                    break;
            }
        }
    }

    if(result)
        [_txn _markChanges: [_original name]];

    return result;
}

- (NSInteger)dataItemsCountForKey: (NSData *)key;
{
    NSInteger result = 0;
    MDB_cursor *cursor;
    MDB_val _key;
    MDB_val _data;

    _key.mv_size = [key length];
    _key.mv_data = (void *)[key bytes];

    int rc = mdb_cursor_open([_txn txn], [_original dbi], &cursor);

    if(rc == 0)
    {
        rc = mdb_cursor_get(cursor, &_key, &_data, MDB_SET);

        if(rc == 0)
        {
            size_t countptr;

            rc = mdb_cursor_count(cursor, &countptr);
            result = countptr;
        }

        mdb_cursor_close(cursor);
    }

    return rc == 0 ? result : 0;
}

- (NSArray *)dataItemsForKey: (NSData *)key;
{
    __block NSMutableArray *result = [[NSMutableArray alloc] init];

    [self enumerateDataItemsForKey: key
                      usingBlock:^(NSData *data, NSInteger index, BOOL *stop) {
                          [result addObject: data];
                      }];

    return result;
}

- (NSData *)dataItemForKey: (NSData *)key atIndex: (NSInteger)index;
{
    __block NSData *result = nil;
    [self enumerateDataItemsForKey: key
                      usingBlock:^(NSData *data, NSInteger lindex, BOOL *stop) {
                          if(lindex == index)
                          {
                              result = data;
                              *stop = YES;
                          }
                      }];

    return result;
}

- (NSData *)lastDataItemForKey: (NSData *)key;
{
    NSData *result = nil;

    if([_original allowDuplicatedKeys])
    {
        MDB_cursor *cursor;
        MDB_val _key, _data;

        _key.mv_size = [key length];
        _key.mv_data = (void *)[key bytes];

        int rc = mdb_cursor_open([_txn txn], [_original dbi], &cursor);

        if(rc == 0)
        {
            rc = mdb_cursor_get(cursor, &_key, &_data, MDB_SET);

            if(rc == 0)
            {
                rc = mdb_cursor_get(cursor, &_key, &_data, MDB_LAST_DUP);

                if(rc == 0)
                {
                    result = [NSData dataWithBytes: _data.mv_data length: _data.mv_size];
                }
            }

            mdb_cursor_close(cursor);
        }
    }

    return  result;
}

- (NSData *)firstDataItemForKey: (NSData *)key;
{
    NSData *result = nil;

    if([_original allowDuplicatedKeys])
    {
        MDB_cursor *cursor;
        MDB_val _key, _data;

        _key.mv_size = [key length];
        _key.mv_data = (void *)[key bytes];

        int rc = mdb_cursor_open([_txn txn], [_original dbi], &cursor);

        if(rc == 0)
        {
            rc = mdb_cursor_get(cursor, &_key, &_data, MDB_SET_KEY);

            if(rc == 0)
            {
                result = [NSData dataWithBytes: _data.mv_data length: _data.mv_size];
            }

            mdb_cursor_close(cursor);
        }
    }

    return  result;
}

- (BOOL)enumerateDataItemsForKey: (NSData *)key usingBlock: (void (^) (NSData *data, NSInteger index, BOOL *stop))block;
{
    BOOL result = NO;

    if([_original allowDuplicatedKeys])
    {
        MDB_cursor *cursor;
        MDB_val _key, _data;

        _key.mv_size = [key length];
        _key.mv_data = (void *)[key bytes];

        int rc = mdb_cursor_open([_txn txn], [_original dbi], &cursor);

        if(rc == 0)
        {
            rc = mdb_cursor_get(cursor, &_key, &_data, MDB_SET_KEY);

            if(rc == 0)
            {
                result = YES;
                BOOL stop = NO;
                NSInteger index = 0;

                do
                {
                    NSData *dataResult = [NSData dataWithBytes: _data.mv_data length: _data.mv_size];
                    block(dataResult, index, &stop);
                    index++;

                    if(stop)
                        break;
                } while ((rc = mdb_cursor_get(cursor, &_key, &_data, MDB_NEXT_DUP)) == 0);
            }

            mdb_cursor_close(cursor);
        }
    }

    return result;
}

#pragma mark Enumerate Keys and Objects
- (BOOL)enumerateKeysAndDataItemsUsingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: nil returnKey: YES returnData: YES usingBlock: block];
}

- (BOOL)enumerateKeysAndObjectsInDatabaseNamed: (NSString *)name usingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: nil returnKey: YES returnData: YES usingBlock: block];
}

- (BOOL)enumerateKeysAndDataItemsStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: startKey returnKey: YES returnData: YES usingBlock: block];
}

- (BOOL)enumerateKeysAndObjectsInDatabaseNamed: (NSString *)name startWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: startKey returnKey: YES returnData: YES usingBlock: block];
}

#pragma mark Enumerate Keys
- (BOOL)enumerateKeysOnlyUsingBlock: (void (^) (NSData *key, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: nil returnKey: YES returnData: NO usingBlock: ^(NSData *idata, NSData *ikey, NSInteger icount, BOOL *istop) {
        block(ikey, icount, istop);
    }];
}

- (BOOL)enumarteKeysOnlyStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *key, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: startKey returnKey: YES returnData: NO usingBlock: ^(NSData *idata, NSData *ikey, NSInteger icount, BOOL *istop) {
        block(ikey, icount, istop);
    }];
}

#pragma mark Enumerate Objects
- (BOOL)enumerateDataItemsOnlyUsingBlock: (void (^) (NSData *data, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: nil returnKey: NO returnData: YES usingBlock:^(NSData *idata, NSData *ikey, NSInteger icount, BOOL *istop) {
        block(idata, icount, istop);
    }];
}

- (BOOL)enumerateDataItemsOnlyStartWithKey: (NSData *)startKey usingBlock: (void (^) (NSData *data, NSInteger count, BOOL *stop))block;
{
    return [self _enumerateStartAtKey: startKey returnKey: NO returnData: YES usingBlock:^(NSData *idata, NSData *ikey, NSInteger icount, BOOL *istop) {
        block(idata, icount, istop);
    }];
}

#pragma mark Enumerate
- (BOOL)_enumerateStartAtKey: (NSData *)startKey
                   returnKey: (BOOL)rKey
                  returnData: (BOOL)rData
                  usingBlock: (void (^) (NSData *data, NSData *key, NSInteger count, BOOL *stop))block;
{
    BOOL stop = NO;
    MDB_val _key;
    MDB_val _data;

    MDB_cursor *cursor;
    int rc = mdb_cursor_open([_txn txn], [_original dbi], &cursor);

    if(rc != 0)
    {
        mdb_cursor_close(cursor);
        return NO;
    }

    if(startKey)
    {
        _key.mv_size = [startKey length];
        _key.mv_data = (void *)[startKey bytes];

        rc = mdb_cursor_get(cursor, &_key, &_data, MDB_SET_KEY);

        if(rc != 0)
        {
            mdb_cursor_close(cursor);
            return NO;
        }
    }
    else
    {
        rc = mdb_cursor_get(cursor, &_key, &_data, MDB_FIRST);

        if(rc != 0)
        {
            mdb_cursor_close(cursor);
            return NO;
        }
    }

    int next_op = MDB_NEXT;
    if([_original allowDuplicatedKeys])
    {
        next_op = MDB_NEXT_NODUP;
    }

    do
    {
        NSData *dataResult = rData ? [NSData dataWithBytes: _data.mv_data length: _data.mv_size] : nil;
        NSData *keyResult = rKey ? [NSData dataWithBytes: _key.mv_data length: _key.mv_size] : nil;
        NSInteger countResult = 0;

        if(next_op == MDB_NEXT_NODUP)
            countResult = [self dataItemsCountForKey: keyResult];

        block(dataResult, keyResult, countResult, &stop);

        if(stop)
            break;
    } while ((rc = mdb_cursor_get(cursor, &_key, &_data, next_op)) == 0);

    mdb_cursor_close(cursor);

    return YES;
}

@end



