require "spec"
require "../traildb"

UUID = "12345678123456781234567812345678"

# Unfortunately before_each/after_each are global for now, have to do all set here
Spec.before_each do
  cons = TrailDBConstructor.new("testtrail", ["field1", "field2"])
  cons.add(UUID, 1, ["a", "1"])
  cons.add(UUID, 2, ["b", "2"])
  cons.add(UUID, 3, ["c", "3"])
  cons.close

  cons = TrailDBConstructor.new("filtertrail", ["field1", "field2", "field3"])
  cons.add(UUID, 1, ["a", "1", "x"])
  cons.add(UUID, 2, ["b", "2", "x"])
  cons.add(UUID, 3, ["c", "3", "y"])
  cons.add(UUID, 4, ["d", "4", "x"])
  cons.add(UUID, 5, ["e", "5", "x"])
  cons.close
end

Spec.after_each do
  File.delete("testtrail.tdb")
  File.delete("filtertrail.tdb")
end

describe TrailDB do
  it "reads events from a trail" do
    [1, 2, 3].size.should eq 3

    traildb = TrailDB.new("testtrail")
    traildb.num_trails.should eq 1
    trail = traildb[0]
    trail.should be_a TrailDBEventIterator

    # Force evaluation of iterator
    events = trail.map { |event| event.to_h }.to_a
    events.size.should eq 3

    puts events

    # Assert fields individually
    events[0]["field1"].should eq "a"
    events[1]["field1"].should eq "b"
    events[2]["field1"].should eq "c"
    events[0]["field2"].should eq "1"
    events[1]["field2"].should eq "2"
    events[2]["field2"].should eq "3"
  end

  it "reads events from a trail by uuid" do
    [1, 2, 3].size.should eq 3

    traildb = TrailDB.new("testtrail")
    traildb.num_trails.should eq 1
    # trail = traildb[UUID]
    trail = traildb["12345678123456781234567812345678"]
    trail.should be_a TrailDBEventIterator

    # Force evaluation of iterator
    events = trail.map { |event| event.to_h }.to_a

    # Assert full array format
    events.should eq [
      {"field1" => "a", "field2" => "1", "time" => Time.epoch(1)},
      {"field1" => "b", "field2" => "2", "time" => Time.epoch(2)},
      {"field1" => "c", "field2" => "3", "time" => Time.epoch(3)},
    ]
  end

  it "reads trails from a traildb" do
    traildb = TrailDB.new("testtrail.tdb")

    n = 0
    traildb.trails.each do |(uuid, trail)|
      n += 1
      UUID.should eq uuid
      trail.should be_a TrailDBEventIterator
      trail.to_a.size.should eq 3
    end

    n.should eq 1
  end

  it "opens tdbs with and without the extension" do
    File.exists?("testtrail.tdb").should be_true
    File.exists?("testtrail").should be_false
    traildb1 = TrailDB.new("testtrail.tdb")
    traildb2 = TrailDB.new("testtrail")
  end

  it "raises an exception when opening a non-existent tdb" do
    expect_raises TrailDBException do
      TrailDB.new("foo.tdb")
    end
  end

  it "should have the correct fields" do
    traildb = TrailDB.new("testtrail")
    traildb.fields.should eq ["field1", "field2"]
  end

  it "should have the correct uuids" do
    traildb = TrailDB.new("testtrail")
    traildb.get_trail_id(UUID).should eq 0
    traildb.get_uuid(0).should eq UUID
    traildb.includes?(UUID).should be_true
  end

  it "should have the correct lexicon" do
    traildb = TrailDB.new("testtrail")
    traildb.lexicon_size(1).should eq 4
    traildb.lexicon(1).to_a.should eq ["a", "b", "c"]
    traildb.lexicon(2).to_a.should eq ["1", "2", "3"]
    expect_raises TrailDBException do
      traildb.lexicon(3)
    end
  end

  it "should have the correct timestamps" do
    traildb = TrailDB.new("testtrail.tdb")
    traildb.min_timestamp.should eq 1
    traildb.max_timestamp.should eq 3
    traildb.time_range[0].epoch.should eq 1
    traildb.time_range[1].epoch.should eq 3
  end

  it "should not parse timestamps when option is false by id" do
    traildb = TrailDB.new("testtrail.tdb")
    traildb.parse_timestamp = false
    trail = traildb[0]
    events = trail.to_a
    events.map { |event| event.time }.to_a.should eq [1, 2, 3]
  end

  it "should not parse timestamps when option is false when iterating" do
    traildb = TrailDB.new("testtrail.tdb")
    traildb.parse_timestamp = false
    traildb.trails.each do |(uuid, trail)|
      trail.each_with_index do |event, i|
        event.time.should eq i + 1
      end
    end
  end
end

describe TrailDBEventFilter do
  it "should filter simple disjunction" do
    traildb = TrailDB.new("filtertrail")

    # No filter case
    events = traildb[0].to_a
    events.size.should eq 5

    # Add filter
    event_filter = traildb.create_filter([[{"field1", "a"}, {"field2", "4"}]])
    traildb.event_filter = event_filter

    # Smaller dataset
    events = traildb[0].to_a
    events.size.should eq 2

    # Exact comparison
    events[0]["field1"].should eq "a"
    events[0]["field2"].should eq "1"
    events[1]["field1"].should eq "d"
    events[1]["field2"].should eq "4"
  end

  it "should set the event filter with boolean param" do
    traildb = TrailDB.new("filtertrail")
    # With the final parameter true, event filter is automatically applied
    traildb.create_filter([[{"field1", "a"}, {"field2", "4"}]], true)
    events = traildb[0].to_a
    events.size.should eq 2
  end

  it "should filter negation" do
    traildb = TrailDB.new("filtertrail")
    traildb.create_filter([[{"field3", "x", true}]], true)
    events = traildb[0].to_a
    [events[0]["field1"], events[0]["field2"], events[0]["field3"]].should eq ["c", "3", "y"]
  end

  it "should filter conjunction" do
    traildb = TrailDB.new("filtertrail")
    traildb.create_filter([
      [{"field1", "e"}, {"field1", "c"}],
      [{"field3", "y", true}],
    ], true)
    events = traildb[0].to_a
    events.size.should eq 1
    [events[0]["field1"], events[0]["field2"]].should eq ["e", "5"]
  end
end

describe TrailDBConstructor do
  it "should iterate over all fields" do
    cons = TrailDBConstructor.new("testtrail", ["field1", "field2"])
    cons.add(UUID, 1, ["a", "1"])
    cons.add(UUID, 2, ["b", "2"])
    cons.add(UUID, 3, ["c", "3"])
    cons.add(UUID, 4, ["d", "4"])
    cons.add(UUID, 5, ["e", "5"])
    traildb = cons.close

    expect_raises TrailDBException do
      traildb.get_trail_id("12345678123456781234567812345679")
    end

    trail = traildb[traildb.get_trail_id(UUID)]

    j = 1
    trail.each do |event|
      j.to_s.should eq event["field2"]
      j.should eq event.time.as(Time).epoch
      j += 1
    end
    j.should eq 6

    traildb[traildb.get_trail_id(UUID)].map { |e| e["field1"] }.to_a.should eq ["a", "b", "c", "d", "e"]
  end

  it "should create with Time" do
    cons = TrailDBConstructor.new("testtrail", ["field1"])

    events = [{Time.new(2016, 1, 1, 1, 1).to_utc, ["1"]},
              {Time.new(2016, 1, 1, 1, 2).to_utc, ["2"]},
              {Time.new(2016, 1, 1, 1, 3).to_utc, ["3"]}]

    events.each do |(time, values)|
      cons.add(UUID, time, values)
    end

    traildb = cons.close

    traildb[0].each_with_index do |event, i|
      event.time.should be_a Time
      event.time.as(Time).should eq events[i][0]
    end

    traildb.time_range.should eq({events[0][0].to_utc, events[2][0].to_utc})
  end

  it "should work with binary items" do
    binary = "\x00\x01\x02\x00\xff\x00\xff"
    cons = TrailDBConstructor.new("testtrail", ["field1"])
    cons.add(UUID, 123, [binary])
    traildb = cons.close
    events = traildb[0].to_a
    events[0]["field1"].should eq binary
  end

  it "should test full construction" do
    cons = TrailDBConstructor.new("testtrail", ["field1", "field2"])
    cons.add(UUID, 123, ["a"])
    cons.add(UUID, 124, ["b", "c"])
    traildb = cons.close

    traildb.get_trail_id(UUID).should eq 0
    traildb.get_uuid(0).should eq UUID
    traildb.num_trails.should eq 1
    traildb.num_events.should eq 2
    traildb.num_fields.should eq 3

    trails = traildb.trails.to_a
    trails.size.should eq 1
    traildb[UUID].should be_truthy
    traildb.includes?(UUID).should be_true
    traildb.includes?("00000000000000000000000000000000").should be_false

    expect_raises TrailDBException do
      traildb["00000000000000000000000000000000"]
    end

    crumbs = traildb.trails.to_a.map { |(uuid, trail)| trail.to_a }
    trail = crumbs[0]

    trail[0].time.as(Time).epoch.should eq 123
    trail[0]["field1"].should eq "a"
    trail[0]["field2"].should eq ""

    trail[1].time.as(Time).epoch.should eq 124
    trail[1]["field1"].should eq "b"
    trail[1]["field2"].should eq "c"
  end

  it "should append two tdbs" do
    cons = TrailDBConstructor.new("testtrail", ["field1"])
    cons.add(UUID, 123, ["foobarbaz"])
    traildb = cons.close

    cons = TrailDBConstructor.new("testtrail2", ["field1"])
    cons.add(UUID, 124, ["barquuxmoo"])
    cons.append(traildb)
    traildb = cons.close

    traildb.num_events.should eq 2
    trail = traildb.trails.to_a.map { |(uuid, trail)| trail.to_a }[0]

    trail[0].time.as(Time).epoch.should eq 123
    trail[0]["field1"].should eq "foobarbaz"

    trail[1].time.as(Time).epoch.should eq 124
    trail[1]["field1"].should eq "barquuxmoo"

    File.delete("testtrail2.tdb")
  end
end
