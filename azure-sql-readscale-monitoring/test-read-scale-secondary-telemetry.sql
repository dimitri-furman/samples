/*
This script shows how to collect telemetry data from secondary replicas in SSMS. 

Execute this script on the read-only secondary replica.
Data is collected every 10 seconds in an infinite loop. Stop collection by cancelling the query.
Note that collection will stop if the query window in SSMS is closed, or if connection is terminated for any other reason.

In SSMS, connect to the read-only secondary of a database as follows:
1. Make sure that the Read Scale-out feature is enabled. See https://docs.microsoft.com/azure/sql-database/sql-database-read-scale-out.
2. Explicitly specify database name under Connect to Database Engine -> Options -> Connection Properties -> Connect to database.
3. Add ApplicationIntent=ReadOnly under Connect to Database Engine -> Options -> Additional Connection Parameters.

Use the following query to confirm that you are connected to a read-only replica. The result should be READ_ONLY.

SELECT DATABASEPROPERTYEX(DB_NAME(),'Updateability');

For Hyperscale databases with more than one replica, execute this script in multiple query windows.
Each script will output a message in the format "replica_id = <GUID>". 
To ensure that telemetry is collected from all Hyperscale replicas, execute this script in additional query windows 
until you see as many distinct replica_id values in the output as there are replicas.
Query windows that return the same replica_id value as another query window can be closed.
*/

DECLARE @ReplicaID varchar(36);

-- Output replica_id on first iteration to distinguish among multiple Hyperscale read-scale replicas
EXEC telemetry.spLoadResourceStatsOnReadOnly
    @ReplicaID = @ReplicaID OUTPUT;

RAISERROR('replica_id: %s', 0, 1, @ReplicaID) WITH NOWAIT;

WHILE 1 = 1
BEGIN
    EXEC telemetry.spLoadResourceStatsOnReadOnly;
    EXEC telemetry.spLoadDbReplicaStatesOnReadOnly;

    WAITFOR DELAY '00:00:10';
END;
