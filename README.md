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
	- You can create your own Categories for LMDBI like LMDBI+NSPropertyListSerialization
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
                         					        
If you create the Environment with `startImmediatly: YES` the default map size (1024 mb) and maximum number of named databases (32) will be set as default.
Otherwise you have to call `openEnvironmentWithMaxMapSize:` or `openEnvironmentWithMaxMapSize:maximumNumberOfDatabases:` manually.

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
If a modification method like `storeDataItem:forKey`, `removeDataItemForKey`, `addDataItem:toKey:` etc. return `NO` you have to look at the error code in the transaction to check whats happened.

		//This method returns a default LMDBI instance with name __default__ which will create by the Environment on startup
		LMDBI *db = [txn dbi];
		
		//This method will return a LMDBI instance with a given name. If you have a writable transaction the db will created if it doesn't exists.
		LMDBI *db = [txn dbi: @"flower"];
		
		[db storeDataItem: data_value forKey: data_key];
		NSData *data = [db storedDataItemForKey: data_key];
		
		
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
					LMDBI *db = [txn dbi];
					[db storeDataItem: NSDataFromString(@"Birdy") forKey: NSDataFromString(@"key1")];
			
					//add items to a sorted set.
					[db addDataItem: NSDataFromString(@"map value 1") toKey: NSDataFromString(@"mappy")];
					[db addDataItem: NSDataFromString(@"map value 2") toKey: NSDataFromString(@"mappy")];
					[db addDataItem: NSDataFromString(@"map value 3") toKey: NSDataFromString(@"mappy")];
					[db addDataItem: NSDataFromString(@"map value 4") toKey: NSDataFromString(@"mappy")];
			
					//enumerate keys in database
					[db enumerateKeysAndDataItemsUsingBlock:^(NSData *data, NSData *key, NSInteger count, BOOL *stop) {
						NSLog(@"%@ :count %li: %@", NSStringFromData(key), (long)count, NSStringFromData(data));
					}];
		
					//enumerate values stored behinde a key
					[db enumerateDataItemsForKey: NSDataFromString(@"mappy")
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