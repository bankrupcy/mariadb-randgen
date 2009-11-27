# From the manual:
##################
# 5.2.4.3. Mixed Binary Logging Format
# ... automatic switching from statement-based to row-based replication takes place under the following conditions:
# DML updates an NDBCLUSTER table
# When a function contains UUID().
#   --> "value_string"
# When 2 or more tables with AUTO_INCREMENT columns are updated.
#   --> "update","delete"
# When any INSERT DELAYED is executed.
#   --> "insert"
# When the body of a view requires row-based replication, the statement creating the view also uses it — for example, this occurs when the statement creating a view uses the UUID() function.
# When a call to a UDF is involved.
# If a statement is logged by row and the client that executed the statement has any temporary tables, then logging by row is used for all subsequent statements
#    (except for those accessing temporary tables) until all temporary tables in use by that client are dropped.  This is true whether or not any temporary tables are actually logged.
#    Temporary tables cannot be logged using the row-based format; thus, once row-based logging is used, all subsequent statements using that table are unsafe,
#    and we approximate this condition by treating all statements made by that client as unsafe until the client no longer holds any temporary tables.
# When FOUND_ROWS() or ROW_COUNT() is used. (Bug#12092, Bug#30244)
#        SELECT SQL_CALC_FOUND_ROWS * FROM tbl_name
#        WHERE id > 100 LIMIT 10;
#        SELECT FOUND_ROWS();
#    FOUND_ROWS() or ROW_COUNT() are bigint(21) ;
#    Without SQL_CALC_FOUND_ROWS within the previous SELECT, FOUND_ROWS() = number of rows found by this SELECT.
#    --> "value_numeric", but no SQL_CALC_FOUND_ROWS
# When USER(), CURRENT_USER(), or CURRENT_USER is used. (Bug#28086)
#    --> "value_string"
# When a statement refers to one or more system variables. (Bug#31168)
#     --> "shake_clock" affects timestamp
#
# Exception.  The following system variables, when used with session scope (only), do not cause the logging format to switch:
#   * auto_increment_increment * auto_increment_offset
#   * character_set_client * character_set_connection * character_set_database * character_set_server * collation_connection * collation_database * collation_server
#   * foreign_key_checks
#   * identity
#   * last_insert_id
#   * lc_time_names
#   * pseudo_thread_id
#   * sql_auto_is_null
#   * time_zone
#   * timestamp
#     --> "shake_clock" affects timestamp
#   * unique_checks
#   For information about how replication treats sql_mode, see Section 16.3.1.30, “Replication and Variables”.
#   * When one of the tables involved is a log table in the mysql database.
#   * When the LOAD_FILE() function is used. (Bug#39701)
#-----------------------------
# When using statement-based replication, the LOAD DATA INFILE statement's CONCURRENT  option is not replicated;
# that is, LOAD DATA CONCURRENT INFILE is replicated as LOAD DATA INFILE, and LOAD DATA CONCURRENT LOCAL INFILE
# is replicated as LOAD DATA LOCAL INFILE. The CONCURRENT option is replicated when using row-based replication. (Bug#34628)
#-------------------------------
# If you have databases on the master with character sets that differ from the global character_set_server value, you should
# design your CREATE TABLE statements so that tables in those databases do not implicitly rely on the database default character set.
# A good workaround is to state the character set and collation explicitly in CREATE TABLE statements.
#-----------------------------------
# MySQL 5.4.3 and later.   Every CREATE DATABASE IF NOT EXISTS statement is replicated, whether or not the database already exists on
# the master. Similarly, every CREATE TABLE IF NOT EXISTS statement is replicated, whether or not the table already exists on the master.
# This includes CREATE TABLE IF NOT EXISTS ... LIKE. However, replication of CREATE TABLE IF NOT EXISTS ... SELECT follows somewhat
# different rules; see Section 16.3.1.4, “Replication of CREATE TABLE ... SELECT Statements”, for more information.
#
# Replication of CREATE EVENT IF NOT EXISTS.  CREATE EVENT IF NOT EXISTS is always replicated in MySQL 5.4, whether or not the event
# named in this statement already exists on the master.  See also Bug#45574.
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/replication-features-differing-tables.html
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/replication-features-floatvalues.html
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/replication-features-flush.html
#-----------------------------------
# USE LIMIT WITH ORDER BY    $safety_check needs to be switched off otherwise we get a false alarm
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/replication-features-slaveerrors.html
# FOREIGN KEY, master InnoDB and slave MyISAM
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/replication-features-max-allowed-packet.html
# BLOB/TEXT value too big for max-allowed-packet on master or on slave
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/replication-features-timeout.html
# Slave: Innodb detects deadlock -> slave_transaction_retries to run the action to replicate ....
# mleich: Most probably not doable with current RQG
#-----------------------------------
# The same system time zone should be set for both master and slave. If not -> problems with NOW() or FROM_UNIXTIME()
# CONVERT_TZ(...,...,@@session.time_zone)  is properly replicated ...
#-----------------------------------
# In situations where transactions mix updates to transactional and nontransactional tables, the order of statements
# in the binary log is correct, and all needed statements are written to the binary log even in case of a ROLLBACK.
# However, when a second connection updates the nontransactional table before the first connection's transaction is
# complete, statements can be logged out of order, because the second connection's update is written immediately after
# it is performed, regardless of the state of the transaction being performed by the first connection.
#    --> grammar items trans_table , nontrans_table, + use only one sort of table within transaction
#    --> LOCK ALL TABLES + runs transaction with both sorts of tables   ???
#----------------------------------------------------------------------------------------------------------------------
# Due to the nontransactional nature of MyISAM  tables, it is possible to have a statement that only partially updates
# a table and returns an error code. This can happen, for example, on a multiple-row insert that has one row violating
# a key constraint, or if a long update statement is killed after updating some of the rows.
# If that happens on the master, the slave thread exits and waits for the database administrator to decide what to do
# about it unless the error code is legitimate and execution of the statement results in the same error code on the slave.
#-----------------------------------
# When the storage engine type of the slave is nontransactional, transactions on the master that mix updates of transactional
# and nontransactional tables should be avoided because they can cause inconsistency of the data between the master's
# transactional table and the slave's nontransactional table.
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/replication-features-triggers.html !!!!
#-----------------------------------
# TRUNCATE is treated for purposes of logging and replication as DDL rather than DML ...
# --> later
#-----------------------------------
# http://dev.mysql.com/doc/refman/5.4/en/mysqlbinlog-hexdump.html
#    Type 	Name 	Meaning
#    00 	UNKNOWN_EVENT 	This event should never be present in the log.
#    01 	START_EVENT_V3 	This indicates the start of a log file written by MySQL 4 or earlier.
# X  02 	QUERY_EVENT 	The most common type of events. These contain statements executed on the master.
# ?  03 	STOP_EVENT 	Indicates that master has stopped.
# X  04 	ROTATE_EVENT 	Written when the master switches to a new log file.
#        --> "rotate_event"
# X  05 	INTVAR_EVENT 	Used for AUTO_INCREMENT values or when the LAST_INSERT_ID() function is used in the statement.
#        --> "value" contains NULL and (nested) LAST_INSERT_ID()
#    06 	LOAD_EVENT 	Used for LOAD DATA INFILE in MySQL 3.23.
#    07 	SLAVE_EVENT 	Reserved for future use.
#    08 	CREATE_FILE_EVENT 	Used for LOAD DATA INFILE statements. This indicates the start of execution of such a statement. A temporary file is created on the slave. Used in MySQL 4 only.
# X  09 	APPEND_BLOCK_EVENT 	Contains data for use in a LOAD DATA INFILE statement. The data is stored in the temporary file on the slave.
#        --> "dml" contains LOAD DATA
#    0a 	EXEC_LOAD_EVENT 	Used for LOAD DATA INFILE statements. The contents of the temporary file is stored in the table on the slave. Used in MySQL 4 only.
# X  0b 	DELETE_FILE_EVENT 	Rollback of a LOAD DATA INFILE statement. The temporary file should be deleted on the slave.
#        --> "dml" contains LOAD DATA
#    0c 	NEW_LOAD_EVENT 	Used for LOAD DATA INFILE in MySQL 4 and earlier.
# X  0d 	RAND_EVENT 	Used to send information about random values if the RAND() function is used in the statement.
#        --> "value_rand"
# X  0e 	USER_VAR_EVENT 	Used to replicate user variables.
#        --> "dml" containing SET @aux + "values" containg @aux
# X  0f 	FORMAT_DESCRIPTION_EVENT 	This indicates the start of a log file written by MySQL 5 or later.
#        --> ?
# X  10 	XID_EVENT 	Event indicating commit of an XA transaction.
# X  11 	BEGIN_LOAD_QUERY_EVENT 	Used for LOAD DATA INFILE statements in MySQL 5 and later.
# X  12 	EXECUTE_LOAD_QUERY_EVENT 	Used for LOAD DATA INFILE statements in MySQL 5 and later.
#        --> "dml" contains LOAD DATA
# X  13 	TABLE_MAP_EVENT 	Information about a table definition. Used in MySQL 5.1.5 and later.
#    14 	PRE_GA_WRITE_ROWS_EVENT 	Row data for a single table that should be created. Used in MySQL 5.1.5 to 5.1.17.
#    15 	PRE_GA_UPDATE_ROWS_EVENT 	Row data for a single table that needs to be updated. Used in MySQL 5.1.5 to 5.1.17.
#    16 	PRE_GA_DELETE_ROWS_EVENT 	Row data for a single table that should be deleted. Used in MySQL 5.1.5 to 5.1.17.
# X  17 	WRITE_ROWS_EVENT 	Row data for a single table that should be created. Used in MySQL 5.1.18 and later.
#        --> insert
# X  18 	UPDATE_ROWS_EVENT 	Row data for a single table that needs to be updated. Used in MySQL 5.1.18 and later.
#        --> update
# X  19 	DELETE_ROWS_EVENT 	Row data for a single table that should be deleted. Used in MySQL 5.1.18 and later.
#        --> delete
# 1a 	INCIDENT_EVENT 	Something out of the ordinary happened. Added in MySQL 5.1.18.
# My (mleich) markings:
# X needs sub test
# I most probably already covered (FIXME: Check in hex dump)

query:
	binlog_event ;

query_init:
	# 1. Bernt says an early metadata query helps to avoid the RQG RC = 255 problem.
	# 2. For debugging the grammar :   $safety_check = "/* QUERY_IS_REPLICATION_SAFE */"
	#    For faster execution      :   $safety_check = ""
	SELECT ' _table ', ' _field ' ; { $safety_check = "/* QUERY_IS_REPLICATION_SAFE */" ; return undef } ;
	# SELECT ' _table ', ' _field ' ; { $safety_check = "" ; return undef } ;

binlog_event:
	/* BEGIN 1 */ single_dml_event    /* 1 END */  |
	/* BEGIN 2 */ single_dml_event    /* 2 END */  |
	/* BEGIN 3 */ sequence_dml_event  /* 3 END */  |
	# xid_event |
	set_iso_level      |
	shake_clock        |
	rotate_event       ;

set_iso_level:
	{ return $safety_check } SET global_or_session TRANSACTION ISOLATION LEVEL iso_level ;
iso_level:
	# READ UNCOMMITTED , READ COMMITTED are not safe for InnoDB and binary logging in mode STATEMENT
	# Will the next work like expected?
	{ if ( $format == 'STATEMENT' ) { return 'REPEATABLE READ' } else { return 'READ UNCOMMITTED' } } |
	{ if ( $format == 'STATEMENT' ) { return 'SERIALIZABLE'    } else { return 'READ COMMITTED'   } } |
	REPEATABLE READ | SERIALIZABLE ;

global_or_session:
	SESSION | GLOBAL ;

shake_clock:
	{ return $safety_check } SET SESSION TIMESTAMP = UNIX_TIMESTAMP() plus_minus _digit ;
plus_minus:
	+ | - ;

rotate_event:
	# Cause that the master switches to a new binary log file 
	#    ? RESET MASTER ?
	{ return $safety_check } FLUSH LOGS ;
	
xid_event:
	# Omit BEGIN because it is only an alias for START TRANSACTION
	START TRANSACTION | COMMIT | ROLLBACK |
	SAVEPOINT A | ROLLBACK TO SAVEPOINT A | RELEASE SAVEPOINT A |
	implicit_commit ;

implicit_commit:
	# mleich: A failing (<> wrong syntax) CREATE TABLE make also an implicite COMMIT
	#         RPL has problems with concurrent DDL but is this also valid for a
	#         CREATE TABLE <already exists> AS SELECT 1 AS my_col   ?
	# CREATE DATABASE ic ; CREATE TABLE ic . _letter SELECT * FROM _table LIMIT digit ; DROP DATABASE ic |
	# CREATE USER _letter | DROP USER _letter | RENAME USER _letter TO _letter |
	SET AUTOCOMMIT = ON | SET AUTOCOMMIT = OFF |
	# CREATE TABLE IF NOT EXISTS _letter ENGINE = engine SELECT * FROM _table LIMIT digit |
	# RENAME TABLE _letter TO _letter |
	# TRUNCATE TABLE _letter |
	# DROP TABLE IF EXISTS _letter |
	# Grant/Revoke
	# FLUSH
	# LOAD DATA INFILE causes an implicit commit only for tables using the NDB storage engine
	{ return $safety_check } LOCK TABLE _table WRITE ; { return $safety_check } UNLOCK TABLES ;

single_dml_event:
	binlog_format_save ; binlog_format_set ; dml ; binlog_format_restore ;
sequence_dml_event:
	binlog_format_save ; binlog_format_set ; START TRANSACTION ; dml ; dml ; dml ; dml ;dml ; dml ; dml ; dml ; dml ; dml ; dml ; dml ; dml ; dml ; dml ; dml ;  COMMIT ; binlog_format_restore ;

binlog_format_save:
	{ return $safety_check } SET @binlog_format_saved = @@binlog_format ;
binlog_format_set:
	{ return $safety_check } SET BINLOG_FORMAT = rand_binlog_format ;
binlog_format_restore:
	SET BINLOG_FORMAT = @binlog_format_saved ;
rand_binlog_format:
	# 'STATEMENT' | 'MIXED' | 'ROW' ;
	# FIXME: Do we need to adjust $format when executing binlog_format_save or binlog_format_restore ?
	{ $val = $prng->int(0,2); if ($val == 0) { $format = 'STATEMENT' } elsif ($val == 1) {$format = 'MIXED'} else {$format = 'ROW'} ; return $format} ;

dml:
	# LOAD DATA is temporary disabled
	# generate_outfile ; { return $safety_check } LOAD DATA concurrent_or_empty INFILE tmpnam REPLACE INTO TABLE _table |
	{ return $safety_check } update |
	{ return $safety_check } delete |
	{ return $safety_check } insert |
	# generate_outfile ; { return $safety_check } PREPARE st1 FROM "LOAD DATA INFILE tmpnam REPLACE INTO TABLE _table" ; { return $safety_check } EXECUTE st1 ; DEALLOCATE PREPARE st1 |
	{ return $safety_check } PREPARE st1 FROM " update " ; { return $safety_check } EXECUTE st1 ; DEALLOCATE PREPARE st1 |
	{ return $safety_check } PREPARE st1 FROM " delete " ; { return $safety_check } EXECUTE st1 ; DEALLOCATE PREPARE st1 |
	{ return $safety_check } PREPARE st1 FROM " insert " ; { return $safety_check } EXECUTE st1 ; DEALLOCATE PREPARE st1 |
	# We need the next statement for other statements which should use a user variable.
	{ return $safety_check } SET @aux = value |
	xid_event  ;

generate_outfile:
	SELECT * FROM _table ORDER BY _field INTO OUTFILE tmpnam ;
concurrent_or_empty:
	| CONCURRENT ;

#---------------------

delete:
	# Delete in one table, search in one table
	# Unsafe in statement based replication except we add ORDER BY
	# DELETE       FROM _table            LIMIT 1   |
	DELETE       FROM _table               where    |
	# Delete in two tables, search in two tables
	DELETE A , B FROM _table AS A join     where    |
	# Delete in one table, search in two tables
	DELETE A     FROM _table AS A where subquery    ;

join:
	# Do not place a where condition here.
	NATURAL JOIN _table B ;
subquery:
	correlated | non_correlated ;
subquery_part1:
	AND A.`pk` IN ( SELECT `pk` FROM _table AS B  ;
correlated:
	subquery_part1 WHERE B.`pk` = A.`pk` ) ;
non_correlated:
	subquery_part1 ) ;
where:
	WHERE `pk` BETWEEN _digit[invariant] AND _digit[invariant] + 1 ;

insert:
	# mleich: Does an additional "on_duplicate_key_update" give an advantage?
	# Insert into one table, search in no other table
	INSERT delayed_or_empty INTO _table ( _field ) VALUES ( value ) |
	# Insert into one table, search in >= 1 tables
	INSERT delayed_or_empty INTO _table ( _field_list[invariant] ) SELECT _field_list[invariant] FROM table_in_select AS A addition ;
delayed_or_empty:
	|
	# DELAYED is unsafe if binlog format = STATEMENT
	{ if ( $format == 'STATEMENT' ) { return '' } else { return 'DELAYED' } } ;

table_in_select:
	_table                                        |
	( SELECT _field_list[invariant] FROM _table ) ;

addition:
	where | where subquery | join where | where union where ;

union:
	UNION SELECT _field_list[invariant] FROM table_in_select AS B ;

update:
	# mleich: Search within another table etc. should be covered by "delete" and "insert".
	# Update one table
	UPDATE _table SET _field = value where |
	# Update two tables
	UPDATE _table AS A join SET A. _field = value , B. _field = _digit where ;

#---------------------

engine:
	Innodb | MyISAM ;

order_by:
	| ORDER BY _field ;

limit:
	| LIMIT digit ;

value:
	value_numeric          |
	value_rand             |
	value_string_converted |
	value_string           |
	value_temporal         |
	@aux                   |
	NULL                   ;

value_numeric:
	# We have 'bit' -> bit(1),'bit(4)','bit(64)','tinyint','smallint','mediumint','int','bigint',
	# 'float','double',
	# 'decimal' -> decimal(10,0),'decimal(35)'
	# mleich: FIXME 1. We do not need all of these values.
	#               2. But a smart distribution of values is required so that we do not hit all time
	#                  outside of the allowed value ranges
	- _digit   | _digit              |
	_bit(1)    | _bit(4)             |
	# _tinyint   | _tinyint_unsigned   |
	# _smallint  | _smallint_unsigned  |
	# _mediumint | _mediumint_unsigned |
	# _int       | _int_unsigned       |
	# _bigint    | _bigint_unsigned    |
	# _bigint    | _bigint_unsigned    |
	# -2.0E+10   | -2.0E+10            |
	-2.0E+100  | -2.0E+100             |
	# int(10)
	CONNECTION_ID()                    |
	# FOUND_ROWS() is bigint(21) and unsafe if binlog format = STATEMENT
	{ if ( $format == 'STATEMENT' ) { return '0' } else { return 'FOUND_ROWS()' } } |
	# ROW_COUNT() is bigint(21) and unsafe if binlog format = STATEMENT
	{ if ( $format == 'STATEMENT' ) { return '0' } else { return 'ROW_COUNT()' } } |
	# Value of the AUTOINCREMENT (per manual only applicable to integer and floating-point types)
	# column for the last INSERT.
	LAST_INSERT_ID()       ;
value_rand:
	RAND() * value_numeric ;

value_string:
	# We have 'char' -> char(1),'char(10)',
	# 'varchar' - varchar(1),'varchar(10)','varchar(257)',
	# 'tinytext','text','mediumtext','longtext',
	#     I fear values > 16 MB are risky, so I omit them.
	# 'enum', 'set'
	# mleich : FIXME Playing with character set etc. is missing
	_char(1)    | _char(10)    |
	_varchar(1) | _varchar(10) | _varchar(257)   |
	# _text(255)  | _text(65535) | _text(16777215) |
	# mleich: _data causes warnings
	#         "Statement may not be safe to log in statement format"
	#         I assume this refers to the risk that an input file
	#         might exist on the master but probably not on the slave.
	#         This is irrelevant for our RQG tests.
	# _data       |
	_set        |
	# UUID() is varchar(36) CHARACTER SET utf8 and unsafe if binlog format = STATEMENT
	{ if ( $format == 'STATEMENT' ) { return 'replacement' } else { return 'UUID()' } } |
	# USER() is varchar(77) CHARACTER SET utf8 and unsafe if binlog format = STATEMENT
	{ if ( $format == 'STATEMENT' ) { return 'replacement' } else { return 'USER()' } } ;

value_string_converted:
	CONVERT( value_string USING character_set );

character_set:
	UTF8 | UCS2 | LATIN1 | BINARY ;

value_temporal:
	# We have 'datetime', 'date', 'timestamp', 'time','year'
	#    _datetime - a date+time value in the ISO format 2000-01-01 00:00:00
	#    _date - a valid date in the range from 2000 to 2010
	#    _timestamp - a date+time value in the MySQL format 20000101000000
	#    _time - a time in the range from 00:00:00 to 29:59:59
	#    _year - a year in the range 2000 to 2010
	_datetime | _date | _time | _datetime | _timestamp |
	NOW() ;
