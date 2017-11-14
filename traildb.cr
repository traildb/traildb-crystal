# C Library type aliases
alias Tdb = Pointer(Void)
alias TdbCons = Pointer(Void)
alias TdbField = UInt32
alias TdbVal = UInt64
alias TdbItem = UInt64
alias TdbCursor = Pointer(Void)
alias TdbError = Int32
alias TdbEventFilter = Pointer(Void)
alias TdbChar = UInt8

@[Link("traildb")]
lib LibTrailDB
  struct TdbEvent
    timestamp : UInt64
    num_items : UInt64
    items : Pointer(TdbItem)
  end

  union TdbOptValue
    ptr : Pointer(Void)
    value : UInt64
  end

  fun tdb_cons_init : TdbCons
  fun tdb_cons_open(TdbCons, Pointer(TdbChar), Pointer(Pointer(TdbChar)), UInt64) : TdbError
  fun tdb_cons_close(TdbCons)
  fun tdb_cons_add(TdbCons, Pointer(UInt8), UInt64, Pointer(Pointer(TdbChar)), Pointer(UInt64)) : TdbError
  fun tdb_cons_append(TdbCons, Tdb) : TdbError
  fun tdb_cons_finalize(TdbCons) : TdbError

  fun tdb_init : Tdb
  fun tdb_open(Tdb, Pointer(TdbChar)) : TdbError
  fun tdb_close(Tdb)

  fun tdb_lexicon_size(Tdb, TdbField) : TdbVal

  fun tdb_get_field(Tdb, Pointer(TdbChar)) : TdbError
  fun tdb_get_field_name(Tdb, TdbField) : Pointer(TdbChar)

  fun tdb_get_item(Tdb, TdbField, Pointer(TdbChar), UInt64) : TdbItem
  fun tdb_get_value(Tdb, TdbField, TdbVal, Pointer(UInt64)) : Pointer(TdbChar)
  fun tdb_get_item_value(Tdb, TdbItem, Pointer(UInt64)) : Pointer(TdbChar)

  fun tdb_get_uuid(Tdb, UInt64) : Pointer(UInt8)
  fun tdb_get_trail_id(Tdb, Pointer(UInt8), Pointer(UInt64)) : TdbError

  fun tdb_error_str(TdbError) : Pointer(TdbChar)

  fun tdb_num_trails(Tdb) : UInt64
  fun tdb_num_events(Tdb) : UInt64
  fun tdb_num_fields(Tdb) : UInt64
  fun tdb_min_timestamp(Tdb) : UInt64
  fun tdb_max_timestamp(Tdb) : UInt64

  fun tdb_version(Tdb) : UInt64

  fun tdb_cursor_new(Tdb) : TdbCursor
  fun tdb_cursor_free(TdbCursor)
  fun tdb_cursor_next(TdbCursor) : Pointer(TdbEvent)
  fun tdb_get_trail(TdbCursor, UInt64) : TdbError
  fun tdb_get_trail_length(TdbCursor) : UInt64
  fun tdb_cursor_set_event_filter(TdbCursor, TdbEventFilter) : TdbError

  fun tdb_event_filter_new : TdbEventFilter
  fun tdb_event_filter_add_term(TdbEventFilter, TdbItem, Int32) : TdbError
  fun tdb_event_filter_add_time_range(UInt64, UInt64) : TdbError
  fun tdb_event_filter_new_clause(TdbEventFilter) : TdbError
  fun tdb_event_filter_new_match_none : TdbEventFilter
  fun tdb_event_filter_new_match_all : TdbEventFilter
  fun tdb_event_filter_free(TdbEventFilter)

  fun tdb_set_opt(Tdb, UInt32, TdbOptValue) : TdbError
  fun tdb_set_trail_opt(Tdb, UInt64, UInt32, TdbOptValue) : TdbError
end

# Crystal Library syntactic sugar
alias TrailDBEvent = Hash(String, String)

def uuid_raw(uuid : String) : Array(UInt8)
end

class TrailDBException < Exception
end

class TrailDBEventIterator
  include Iterator(TrailDBEvent)
  @traildb : TrailDB
  @trailid : UInt64
  @cursor : TdbCursor

  def initialize(@traildb : TrailDB, @trailid : UInt64)
    @cursor = LibTrailDB.tdb_cursor_new(@traildb.db)
    if LibTrailDB.tdb_get_trail(@cursor, @trailid) != 0
      raise TrailDBException.new("Error getting trail #{@trailid}")
    end
  end

  def finalize
    LibTrailDB.tdb_cursor_free(@cursor)
  end

  def next
    event = LibTrailDB.tdb_cursor_next(@cursor)

    if event.null?
      stop
    else
      items = TrailDBEvent.new
      puts event.value
      # puts event.address, , event.value.num_items
      # puts event.value.timestamp
      # puts event.value.num_items
      # puts event.value.items.address
      # if event.value.items.address != 1
      # puts event.value.items.to_slice(event.value.num_items)
      # end

      # puts event.value
      # puts event.value.num_items
      # puts event.value
      # event.value.num_items.times do |item_offset|
      #   # puts event.value.items[item_offset]
      #   # puts @traildb.fields[item_offset]

      #   puts @traildb.get_item_value(event.value.items[item_offset])
      #   items[@traildb.fields[item_offset]] = @traildb.get_item_value(event.value.items[item_offset])
      # end

      items
    end
  end
end

class TrailDBTrailIterator
  include Iterator(TrailDBEventIterator)
  @traildb : TrailDB
  @curr : UInt64

  def initialize(@traildb : TrailDB)
    @curr = 0_u64
  end

  def next
    if @curr >= @traildb.num_trails
      stop
    else
      val = TrailDBEventIterator.new(@traildb, @curr)
      @curr += 1
      val
    end
  end
end

class TrailDBLexicon
  include Iterator(String)
  @traildb : TrailDB
  @fieldish : String
  @curr : TdbVal
  @max : TdbVal

  def initialize(@traildb : TrailDB, @fieldish : String)
    @curr = 0_u64
    @max = @traildb.lexicon_size(@fieldish)
  end

  def next
    if @curr >= @max
      stop
    else
      val = @traildb.get_value(@fieldish, @curr)
      @curr += 1
      val
    end
  end
end

class TrailDB
  @db : Tdb
  @num_trails : UInt64
  @num_events : UInt64
  @num_fields : UInt64
  @fields : Array(String)
  @field_map : Hash(String, TdbField)
  @buffer : Pointer(UInt64)

  getter db
  getter num_trails
  getter num_events
  getter num_fields
  getter fields

  def initialize(path : String)
    @db = LibTrailDB.tdb_init
    res = LibTrailDB.tdb_open(@db, path)

    if res != 0
      raise TrailDBException.new("Could not open #{path}, error code #{res}")
    end

    @num_trails = LibTrailDB.tdb_num_trails(@db)
    @num_events = LibTrailDB.tdb_num_events(@db)
    @num_fields = LibTrailDB.tdb_num_fields(@db)
    @fields = [] of String
    @field_map = {} of String => TdbField

    @num_fields.times.each do |field|
      fieldish = String.new(LibTrailDB.tdb_get_field_name(@db, field))
      @fields << fieldish
      @field_map[fieldish] = field.to_u32
    end

    @buffer = Pointer(UInt64).malloc(2)
  end

  def trails
    TrailDBTrailIterator.new(self)
  end

  def field(fieldish : String) : TdbField
    # Return a field ID given a field name.
    @field_map[fieldish]
  end

  def get_item(fieldish : String, value : String) : TdbItem
    # Return the item corresponding to a field ID or a field name and a string value.
    field = self.field(fieldish)
    item = LibTrailDB.tdb_get_item(@db, field, value, value.size)
    if !item
      raise TrailDBException.new("No such value: #{value}")
    end
    item
  end

  def get_item_value(item : TdbItem) : String
    # Return the string value corresponding to an item.
    value = LibTrailDB.tdb_get_item_value(@db, item, @buffer)
    if !value
      raise TrailDBException.new("Error reading value")
    end
    String.new(value, @buffer.value)
  end

  def get_value(fieldish : String, val : TdbVal) : String
    # Return the string value corresponding to a field ID or a field name and a value ID.
    field = self.field(fieldish)
    value = String.new(LibTrailDB.tdb_get_value(@db, field, val, @buffer))
    if !value
      raise TrailDBException.new("Error reading value")
    end
    String.new(value, @buffer.value)
  end

  def get_uuid(trail_id : UInt64) : String
    # Return UUID given a Trail ID.
    uuid = LibTrailDB.tdb_get_uuid(@db, trail_id)
    if !uuid
      raise TrailDBException.new("Trail ID out of range")
    end
    String.new(uuid, 16)
  end

  def lexicon_size(fieldish : String) : TdbVal
    # Return the number of distinct values in the given field ID or field name.
    field = self.field(fieldish)
    value = LibTrailDB.tdb_lexicon_size(@db, field)
    if value == 0
      raise TrailDBException.new("Invalid field index")
    end
    value
  end

  def lexicon(fieldish : String)
    # Return an iterator over values of the given field ID or field name.
    return TrailDBLexicon.new(self, fieldish)
  end

  def get_trail_id(uuid)
    # Return Trail ID given a UUID.
    ret = LibTrailDB.tdb_get_trail_id(@db, uuid_raw(uuid), @buffer)
    if ret
      raise TrailDBException.new("UUID '#{uuid}' not found")
    end
    @buffer.value
  end

  def time_range
    # Return the time range covered by this TrailDB.
    tmin = Time.epoch(self.min_timestamp)
    tmax = Time.epoch(self.max_timestamp)
    {tmin, tmax}
  end

  def min_timestamp
    # Return the minimum time stamp of this TrailDB.
    LibTrailDB.tdb_min_timestamp(@db)
  end

  def max_timestamp
    # Return the maximum time stamp of this TrailDB.
    LibTrailDB.tdb_max_timestamp(@db)
  end

  # def create_filter(event_filter)
  #   return TrailDBEventFilter.new(event_filter)
  # end
end

t = TrailDB.new("/mnt/data/wikipedia-history-small.tdb")
# t.lexicon("user").each do |user|
#   puts user
# end

t.trails.each_with_index do |trail, i|
  trail.each do |event|
    # puts "event #{event}"
  end
end
