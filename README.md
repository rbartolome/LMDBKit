LMDBKit
=======
LMDBKit is a Objective-C Wrapper for the [OpenLDAP Lightning Memory-Mapped Database (LMDB)](http://symas.com/mdb/).

LMDB is Licensed under the [OpenLDAP, Public License](http://www.OpenLDAP.org/license.html).  
LMDBKit is Licensed under the [MIT License](http://opensource.org/licenses/mit-license.php).

LMDB Source is part of the OpenLDAP [Repository](git://git.openldap.org/openldap.git).

Beside the **LMDBKit** source files you need the following files from liblmdb:  

		- midl.h  
		- midl.c  
		- lmdb.h  
		- mdb.c  

Definition
----------
- Keys and Values are of type NSData.
- 2 types of Transactions are supported:
	- readonly (blocks will execute in a concurrent queue)
	- read/write (blocks will execute in a serial queue)
- Open a non existing database in a readonly transaction will fail.
- If a parent transaction is readonly the nested transaction must be readonly too.

Workflow:
--------

**Open a Environment:**

	    LMDBEnvironment *env = [[LMDBEnvironment alloc] initWithPath: @"/path_to/my_lmdb"
                         					        startImmediately: YES];
                         					        
If you create the Environment with `startImmediatly: YES` the default map size (1024) and maximum number of named databases (32) will be set as default.  
Otherwise you have to call `openEnvironmentWithMapSize:` or `openEnvironmentWithMapSize:maximumNumberOfDatabases:` manually.

**Create a Database outside of a Transaction:**

		[env openDatabaseNamed: @"my_new_database"];
		

**Manual Transaction handling:**

		LMDBTransaction *txn = [env beginTransactionWithParent: nil readonly: NO];
		...
		/**
		 * If you want to rollback your changes or you have a readonly transaction you can call abort otherwise commit
		 * [env abortTransaction: txn];
		 **/
		[env commitTransaction: txn error: &error];
		
		
**Block based Transaction handling:**

		[env transaction: ^(LMDBTransaction *txn, BOOL *rollback) {
    				...
    		  }
      		  completion: ^(NSError *error) {
        			NSLog(@"%@", error ? [error description] : @"No error on completion");
        }];
    	
**Accessing the Database from a Transaction:**

After you a have a Transaction you can add, remove and search data.  
If a `set`, `del`, `sadd`, `sdel` or `srep` method returns `NO` you have to look at the error code in the transaction to check whats happened.

		//This method returns a default LMDBI instance with name __default__ which will create by the Environment on startup
		LMDBI *db = [txn db];
		
		//This method will return a LMDBI instance with a given name. If you have a writable transaction the db will created if it doesn't exists.
		LMDBI *db = [txn db: @"flower"];
		
		[db set: data_value key: data_key];
		NSData *data = [db get: data_key];
		
		
**Transaction Errors:**

		enum {
		    LMDBKitErrorCodeUnknown = 0,
    		LMDBKitErrorCodeDatabaseFull,
    		LMDBKitErrorCodeTransactionFull,
    		LMDBKitErrorCodeTransactionCommitFailedError,
		    LMDBKitErrorCodeAttemptToWriteInReadOnlyTransaction
		};

		
Example:
--------

	    LMDBEnvironment *env = [[LMDBEnvironment alloc] initWithPath: @"/path_to/my_lmdb"
                         					        startImmediately: YES];
                         					        
        [env transaction: ^(LMDBTransaction *txn, BOOL *rollback) {
					NSError *error = nil;
					LMDBI *db = [txn db];
					[db set: NSDataFromString(@"Birdy") key: NSDataFromString(@"key1") error: &error];
			
					//Sorted Set Methods have a 's' prefix.
					[db sadd: NSDataFromString(@"map value 1") key: NSDataFromString(@"mappy") error: &error];
					[db sadd: NSDataFromString(@"map value 2") key: NSDataFromString(@"mappy") error: &error];
					[db sadd: NSDataFromString(@"map value 3") key: NSDataFromString(@"mappy") error: &error];
					[db sadd: NSDataFromString(@"map value 4") key: NSDataFromString(@"mappy") error: &error];
			
					//Enumerate keys in database
					[db enumerateKeysAndObjectsUsingBlock:^(NSData *data, NSData *key, NSInteger count, BOOL *stop) {
						NSLog(@"%@ :count %li: %@", NSStringFromData(key), (long)count, NSStringFromData(data));
					}];
		
					//Enumerate values stored behinde a key
					[db senumerateObjectsForKey: NSDataFromString(@"mappy")
						 usingBlock:^(NSData *data, NSInteger index, BOOL *stop) {
								NSLog(@"- mappy values :index %li: %@", (long)index, NSStringFromData(data));
					}];
			
					*rollback = YES;
    		  }
      		  completion: ^(NSError *error) {
        			NSLog(@"%@", error ? [error description] : @"No error on completion");
        	  }
        ];
        

ToDo:
-----

• Test on iOS