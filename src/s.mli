module type IO = sig
  type 'a t

  type fd
  type in_channel
  type out_channel

  type 'a stream
  type stream_count

  val connect : string -> int -> fd t
  val close : fd -> unit t
  val sleep : float -> unit t

  val (>>=) : 'a t -> ('a -> 'b t) -> 'b t
  val catch : (unit -> 'a t) -> (exn -> 'a t) -> 'a t
  val try_bind : (unit -> 'a t) -> ('a -> 'b t) -> (exn -> 'b t) -> 'b t
  val ignore_result : 'a t -> unit
  val return : 'a -> 'a t
  val fail : exn -> 'a t
  val run : 'a t -> 'a

  val in_channel_of_descr : fd -> in_channel
  val out_channel_of_descr : fd -> out_channel
  val input_char : in_channel -> char t
  val really_input : in_channel -> string -> int -> int -> unit t
  val output_string : out_channel -> string -> unit t
  val flush : out_channel -> unit t

  val iter : ('a -> unit t) -> 'a list -> unit t
  val iter_serial : ('a -> unit t) -> 'a list -> unit t
  val map : ('a -> 'b t) -> 'a list -> 'b list t
  val map_serial : ('a -> 'b t) -> 'a list -> 'b list t
  val fold_left : ('a -> 'b -> 'a t) -> 'a -> 'b list -> 'a t

  val stream_from : (stream_count -> 'b option t) -> 'b stream
  val stream_next: 'a stream -> 'a t

end

module type Client = sig
  module IO : IO

  (** {6 Types and exceptions } *)

  type reply = [
    | `Status of string
    | `Error of string
    | `Int of int
    | `Int64 of Int64.t
    | `Bulk of string option
    | `Multibulk of reply list
  ]

  type connection = private {
    fd     : IO.fd;
    in_ch  : IO.in_channel;
    out_ch : IO.out_channel;
    stream : reply list IO.stream;
  }

  (** Error responses from server *)
  exception Error of string

  (** Protocol errors *)
  exception Unexpected of reply
  exception Unrecognized of string * string (* explanation, data *)

  (** Server connection info *)
  type connection_spec = {
    host : string;
    port : int;
  }

  (** Possible BITOP operations *)
  type bit_operation = AND | OR | XOR | NOT


  (** {6 Connection handling } *)

  val connect : connection_spec -> connection IO.t
  val disconnect : connection -> unit IO.t
  val with_connection : connection_spec -> (connection -> 'a IO.t) -> 'a IO.t
  val stream : connection -> reply list IO.stream

  (** {6 Connection commands } *)

  (** Authenticate to server. *)
  val auth : connection -> string -> unit IO.t

  (** Echo given string. *)
  val echo : connection -> string -> string option IO.t

  (** Ping connection; returns [ true ] if ping was successfull. *)
  val ping : connection -> bool IO.t

  (** Close connection. *)
  val quit : connection -> unit IO.t

  (** Switch to a different db; raises {!Error} if index is invalid. *)
  val select : connection -> int -> unit IO.t

  (** {6 Keys commands} *)

  (** Delete a key; returns the number of keys removed. *)
  val del : connection -> string list -> int IO.t

  (** Determine if a key exists. *)
  val exists : connection -> string -> bool IO.t

  (** Set a key's time to live in seconds; returns [ true ] if timeout was set, false otherwise. *)
  val expire : connection -> string -> int -> bool IO.t

  (** Set a key's time to live in milliseconds; returns [ true ] if timeout was set, false otherwise. *)
  val pexpire : connection -> string -> int -> bool IO.t

  (** Set the expiration for a key as a UNIX timestamp, the time is truncated to the nearest second; returns [ true ] if timeout was set, [ false ] otherwise. *)
  val expireat : connection -> string -> float -> bool IO.t

  (** Set the expiration for a key as a UNIX timestamp in milliseconds; returns [ true ] if timeout was set, [ false ] otherwise. *)
  val pexpireat : connection -> string -> int -> bool IO.t

  (** Find all keys matching the given pattern. *)
  val keys : connection -> string -> string list IO.t

  (** Incrementally iterate the keys space; see tests for usage example. *)
  val scan : ?pattern:string -> ?count:int -> connection -> int -> (int * string list) IO.t

  (** Move key to a different db; returns [ true ] if key was moved, [ false ] otherwise. *)
  val move : connection -> string -> int -> bool IO.t

  (** Remove timeout on key; returns [ true ] if timeout was removed, [ false ] otherwise. *)
  val persist : connection -> string -> bool IO.t

  (** Return a random key from the keyspace; returns [ None ] if db is empty. *)
  val randomkey : connection -> string option IO.t

  (** Rename a key; raises {!Error} if key doesn't exist. *)
  val rename : connection -> string -> string -> unit IO.t

  (** Rename a key, only if the new key does not exist; returns [ true ] if key was renamed, [ false ] if newkey already exists. *)
  val renamenx : connection -> string -> string -> bool IO.t

  (** Sort elements in a list, set or sorted set; return sorted list of items. *)
  val sort :
    connection ->
    ?by:string ->
    ?limit:int * int ->
    ?get:'a list ->
    ?order:[< `Asc | `Desc ] -> ?alpha:bool -> string -> string list IO.t

  (** Sort and store elements in a list, set or sorted set; returns length of sorted items list which was stored. *)
  val sort_and_store :
    connection ->
    ?by:string ->
    ?limit:int * int ->
    ?get:'a list ->
    ?order:[< `Asc | `Desc ] ->
    ?alpha:bool -> string -> string -> int IO.t

  (** Time to live for a key in seconds; returns [ None ] if key doesn't exist or doesn't have a timeout. *)
  val ttl : connection -> string -> int option IO.t

  (** Time to live for a key in milliseconds; returns [ None ] if key doesn't exist or doesn't have a timeout. *)
  val pttl : connection -> string -> int option IO.t

  (** Determine the type stored as key. *)
  val type_of : connection -> string -> [> `Hash | `List | `None | `String | `Zset ] IO.t

  (** Return a serialized version of the value stored at the specified key; returns [ None ] if key doesn't exist. *)
  val dump: connection -> string -> string option IO.t

  (** Create a key with serialized value (obtained via DUMP). *)
  val restore: connection -> string -> int -> string -> unit IO.t

  (** Inspect the internals of Redis objects; returns the number of references of the value associated with the specified key. *)
  val object_refcount: connection -> string -> int option IO.t

  (** Inspect the internals of Redis objects; returns the kind of internal representation used in order to store the value associated with a key. *)
  val object_encoding: connection -> string -> string option IO.t

  (** Inspect the internals of Redis objects; returns the number of seconds since the object stored at the specified key is idle. *)
  val object_idletime: connection -> string -> int option IO.t

  (** {6 String commands} *)

  (** Append a value to a key; returns length of string after append. *)
  val append : connection -> string -> string -> int IO.t

  (** Sets or clears the bit at offset in the string value stored at key. *)
  val setbit : connection -> string -> int -> int -> int IO.t

  (** Returns the bit value at offset in the string value stored at key. *)
  val getbit : connection -> string -> int -> int IO.t

  (** Perform a bitwise operation between multiple keys (containing string values) and store the result in the destination key.
      See {!bit_operation} type for available operations. *)
  val bitop : connection -> bit_operation -> string -> string list -> int IO.t

  (** Count the number of set bits (population counting) in a string. *)
  val bitcount : ?first:int -> ?last:int -> connection -> string -> int IO.t

  (** Return the position of the first bit set to 1 or 0 in a string. *)
  val bitpos : ?first:int -> ?last:int -> connection -> string -> int -> int IO.t

  (** Decrements the number stored at key by one. If the key does not exist, it is set to 0 before performing the operation. *)
  val decr : connection -> string -> int IO.t

  (** Decrements the number stored at key by decrement. If the key does not exist, it is set to 0 before performing the operation. *)
  val decrby : connection -> string -> int -> int IO.t

  (** Get the value of key. *)
  val get : connection -> string -> string option IO.t

  (** Returns the substring of the string value stored at key, determined by the offsets start and end (both are inclusive). *)
  val getrange : connection -> string -> int -> int -> string option IO.t

  (** Atomically sets key to value and returns the old value stored at key. Returns [ None ] when key exists but does not hold a string value. *)
  val getset : connection -> string -> string -> string option IO.t

  (** Increments the number stored at key by one. If the key does not exist, it is set to 0 before performing the operation. *)
  val incr : connection -> string -> int IO.t

  (** Increments the number stored at key by increment. If the key does not exist, it is set to 0 before performing the operation. *)
  val incrby : connection -> string -> int -> int IO.t

  (** Increment the string representing a floating point number stored at key by the specified increment. If the key does not exist, it is set to 0 before performing the operation. *)
  val incrbyfloat : connection -> string -> float -> float IO.t

  (** Returns the values of all specified keys. *)
  val mget : connection -> string list -> string option list IO.t

  (** Sets the given keys to their respective values. *)
  val mset : connection -> (string * string) list -> unit IO.t

  (** Sets the given keys to their respective values. MSETNX will not perform any operation at all even if just a single key already exists. *)
  val msetnx : connection -> (string * string) list -> bool IO.t

  (** Set key to hold the string value. *)
  val set : connection -> string -> string -> unit IO.t

  (** Set key to hold the string value and set key to timeout after a given number of seconds. *)
  val setex : connection -> string -> int -> string -> unit IO.t

  (** PSETEX works exactly like SETEX with the sole difference that the expire time is specified in milliseconds instead of seconds. *)
  val psetex : connection -> string -> int -> string -> unit IO.t

  (** Set key to hold string value if key does not exist. *)
  val setnx : connection -> string -> string -> bool IO.t

  (** Overwrites part of the string stored at key, starting at the specified offset, for the entire length of value. *)
  val setrange : connection -> string -> int -> string -> int IO.t

  (** Returns the length of the string value stored at key. An error is returned when key holds a non-string value. *)
  val strlen : connection -> string -> int IO.t

  (** {6 Hash commands} *)

  (** Removes the specified fields from the hash stored at key. Specified fields that do not exist within this hash are ignored. *)
  val hdel : connection -> string -> string -> bool IO.t

  (** Returns if field is an existing field in the hash stored at key. *)
  val hexists : connection -> string -> string -> bool IO.t

  (** Returns the value associated with field in the hash stored at key. *)
  val hget : connection -> string -> string -> string option IO.t

  (** Returns all fields and values of the hash stored at key. *)
  val hgetall : connection -> string -> (string * string) list IO.t

  (** Increments the number stored at field in the hash stored at key by increment. *)
  val hincrby : connection -> string -> string -> int -> int IO.t

  (** Returns all field names in the hash stored at key. *)
  val hkeys : connection -> string -> string list IO.t

  (** Returns the number of fields contained in the hash stored at key. *)
  val hlen : connection -> string -> int IO.t

  (** Returns the values associated with the specified fields in the hash stored at key. *)
  val hmget : connection -> string -> string list -> string option list IO.t

  (** Sets the specified fields to their respective values in the hash stored at key. *)
  val hmset : connection -> string -> (string * string) list -> unit IO.t

  (** Sets field in the hash stored at key to value. *)
  val hset : connection -> string -> string -> string -> bool IO.t

  (** Sets field in the hash stored at key to value, only if field does not yet exist. *)
  val hsetnx : connection -> string -> string -> string -> bool IO.t

  (** Returns all values in the hash stored at key. *)
  val hvals : connection -> string -> string list IO.t

  (** {6 List commands} *)

  (* Blocks while all of the lists are empty. Set timeout to number of seconds OR 0 to block indefinitely. *)
  val blpop : connection -> string list -> int -> (string * string) option IO.t

  (* Same as BLPOP except pulling the last instead of first element. *)
  val brpop : connection -> string list -> int -> (string * string) option IO.t

  (* Blocking RPOPLPUSH.  Returns None on timeout. *)
  val brpoplpush : connection -> string -> string -> int -> string option IO.t

  (* Out of range or nonexistent key will return None. *)
  val lindex : connection -> string -> int -> string option IO.t

  (* Returns None if pivot isn't found, otherwise returns length of list after insert. *)
  val linsert : connection -> string -> [< `After | `Before ] -> string -> string -> int option IO.t

  val llen : connection -> string -> int IO.t

  val lpop : connection -> string -> string option IO.t

  (* Returns length of list after operation. *)
  val lpush : connection -> string -> string -> int IO.t

  (* Only push when list exists. Return length of list after operation. *)
  val lpushx : connection -> string -> string -> int IO.t

  (* Out of range arguments are handled by limiting to valid range. *)
  val lrange : connection -> string -> int -> int -> string list IO.t

  (* Returns number of elements removed. *)
  val lrem : connection -> string -> int -> string -> int IO.t

  (* Raises Error if out of range. *)
  val lset : connection -> string -> int -> string -> unit IO.t

  (* Removes all but the specified range. Out of range arguments are handled by limiting to valid range. *)
  val ltrim : connection -> string -> int -> int -> unit IO.t

  val rpop : connection -> string -> string option IO.t

  (* Remove last element of source and insert as first element of destination. Returns the element moved
     or None if source is empty. *)
  val rpoplpush : connection -> string -> string -> string option IO.t

  (* Returns length of list after operation. *)
  val rpush : connection -> string -> string -> int IO.t

  val rpushx : connection -> string -> string -> int IO.t

  (** {6 Set commands} *)

  (* Returns true if member was added, false otherwise. *)
  val sadd : connection -> string -> string -> bool IO.t

  val scard : connection -> string -> int IO.t

  (* Difference between first and all successive sets. *)
  val sdiff : connection -> string list -> string list IO.t

  (* like sdiff, but store result in destination. returns size of result. *)
  val sdiffstore : connection -> string -> string list -> int IO.t

  val sinter : connection -> string list -> string list IO.t

  (* Like SINTER, but store result in destination. Returns size of result. *)
  val sinterstore : connection -> string -> string list -> int IO.t

  val sismember : connection -> string -> string -> bool IO.t

  val smembers : connection -> string -> string list IO.t

  (* Returns true if an element was moved, false otherwise. *)
  val smove : connection -> string -> string -> string -> bool IO.t

  (* Remove random element from set. *)
  val spop : connection -> string -> string option IO.t

  (* Like SPOP, but doesn't remove chosen element. *)
  val srandmember : connection -> string -> string option IO.t

  (* Returns true if element was removed. *)
  val srem : connection -> string -> string -> bool IO.t

  val sunion : connection -> string list -> string list IO.t

  (* Like SUNION, but store result in destination. Returns size of result. *)
  val sunionstore : connection -> string -> string list -> int IO.t

  (** {6 Pub/sub commands} *)

  (* Post a message to a channel. Returns number of clients that received the message. *)
  val publish : connection -> string -> string -> int IO.t

  (* Lists the currently active channels. If no pattern is specified, all channels are listed. *)
  val pubsub_channels : connection -> string option -> reply list IO.t

  (* Returns the number of subscribers (not counting clients subscribed to patterns) for the specified channels. *)
  val pubsub_numsub : connection -> string list -> reply list IO.t

  (* Subscribes the client to the specified channels. *)
  val subscribe : connection -> string list -> unit IO.t

  (* Unsubscribes the client from the given channels, or from all of them if an empty list is given *)
  val unsubscribe : connection -> string list -> unit IO.t

  (* Subscribes the client to the given patterns. *)
  val psubscribe : connection -> string list -> unit IO.t

  (* Unsubscribes the client from the given patterns. *)
  val punsubscribe : connection -> string list -> unit IO.t

  (** {6 Sorted set commands} *)

  (* Add one or more members to a sorted set, or update its score if it already exists. *)
  val zadd : connection -> string -> (int * string) list -> int IO.t

  (* Return a range of members in a sorted set, by index. *)
  val zrange : connection -> ?withscores:bool -> string -> int -> int -> reply list IO.t

  (* Return a range of members in a sorted set, by score. *)
  val zrangebyscore : connection -> ?withscores:bool -> string -> int -> int -> reply list IO.t

  (* Remove one or more members from a sorted set. *)
  val zrem : connection -> string list -> int IO.t

  (** {6 Transaction commands} *)

  (* Marks the start of a transaction block. Subsequent commands will be queued for atomic execution using EXEC. *)
  val multi : connection -> unit IO.t

  (* Executes all previously queued commands in a transaction and restores the connection state to normal. *)
  val exec : connection -> reply list IO.t

  (* Flushes all previously queued commands in a transaction and restores the connection state to normal. *)
  val discard : connection -> unit IO.t

  (* Marks the given keys to be watched for conditional execution of a transaction. *)
  val watch : connection -> string list -> unit IO.t

  (* Flushes all the previously watched keys for a transaction. *)
  val unwatch : connection -> unit IO.t

  val queue : (unit -> 'a IO.t) -> unit IO.t

  (** {6 Scripting commands} *)

  (* Load the specified Lua script into the script cache. Returns the SHA1 digest of the script for use with EVALSHA. *)
  val script_load : connection -> string -> string IO.t

  (* Evaluates a script using the built-in Lua interpreter. *)
  val eval : connection -> string -> string list -> string list -> reply IO.t

  (* Evaluates a script cached on the server side by its SHA1 digest. *)
  val evalsha : connection -> string -> string list -> string list -> reply IO.t

  (** {6 Server} *)

  val bgrewriteaof : connection -> unit IO.t

  val bgsave : connection -> unit IO.t

  val config_resetstat : connection -> unit IO.t

  val dbsize : connection -> int IO.t

  (* clear all databases *)
  val flushall : connection -> unit IO.t

  (* clear current database *)
  val flushdb : connection -> unit IO.t

  val info : connection -> (string * string) list IO.t

  (* last successful save as Unix timestamp *)
  val lastsave : connection -> float IO.t

  (* role in context of replication *)
  val role : connection -> reply list IO.t

  (* synchronous save *)
  val save : connection -> unit IO.t

  (* save and shutdown server *)
  val shutdown : connection -> unit IO.t
end

module type Cache_params = sig
  type key
  type data

  val cache_key : key -> string
  val cache_expiration : int option

  val data_of_string : string -> data
  val string_of_data : data -> string
end

module type Cache = sig
  module IO : IO
  module Client : Client
  module Params : Cache_params

  val set : Client.connection -> Params.key -> Params.data -> unit IO.t
  val get : Client.connection -> Params.key -> Params.data option IO.t
  val delete : Client.connection -> Params.key -> unit
end

module type Mutex = sig
  module IO : IO
  module Client : Client

  exception Error of string

  val acquire : Client.connection -> ?atime:float -> ?ltime:int -> string -> string -> unit IO.t
  val release : Client.connection -> string -> string -> unit IO.t
  val with_mutex : Client.connection -> ?atime:float -> ?ltime:int -> string -> (unit -> 'a IO.t) -> 'a IO.t
end
