require 'spec_helper'

describe Flexirest::Caching do
  before :each do
    Flexirest::Base._reset_caching!
  end

  context "Configuration of caching" do
    it "should not have caching enabled by default" do
      class CachingExample1
        include Flexirest::Caching
      end
      expect(CachingExample1.perform_caching).to be_falsey
    end

    it "should be able to have caching enabled without affecting Flexirest::Base" do
      class CachingExample2
        include Flexirest::Caching
      end
      CachingExample2.perform_caching true
      expect(CachingExample2.perform_caching).to be_truthy
      expect(Flexirest::Base.perform_caching).to be_falsey
    end

    it "should be possible to enable caching for all objects" do
      class CachingExample3 < Flexirest::Base ; end
      Flexirest::Base._reset_caching!

      expect(Flexirest::Base.perform_caching).to be_falsey

      Flexirest::Base.perform_caching = true
      expect(Flexirest::Base.perform_caching).to be_truthy
      expect(CachingExample3.perform_caching).to be_truthy

      Flexirest::Base._reset_caching!
    end

    it "should be possible to disable caching for each objects" do
      Flexirest::Base.perform_caching = true

      class CachingExample4 < Flexirest::Base; end
      class CachingExample5 < Flexirest::Base
        perform_caching false
      end
      expect(Flexirest::Base.perform_caching).to be_truthy
      expect(CachingExample4.perform_caching).to be_truthy
      expect(CachingExample5.perform_caching).to be_falsey

      Flexirest::Base._reset_caching!
    end

    it "should use Rails.cache if available" do
      begin
        class Rails
          def self.cache
            true
          end
        end
        expect(Flexirest::Base.cache_store).to eq(true)
      ensure
        Object.send(:remove_const, :Rails) if defined?(Rails)
      end
    end

    it "should not error if Rails.cache is not found" do
      begin
        class Rails; end
        expect { Flexirest::Base.cache_store }.not_to raise_error
      ensure
        Object.send(:remove_const, :Rails) if defined?(Rails)
      end
    end

    it "should use a custom cache store if a valid one is manually set" do
      class CachingExampleCacheStore1
        def read(key) ; end
        def write(key, value, options={}) ; end
        def fetch(key, &block) ; end
      end
      cache_store = CachingExampleCacheStore1.new
      Flexirest::Base.cache_store = cache_store
      expect(Flexirest::Base.cache_store).to eq(cache_store)
    end

    it "should error if you try to use a custom cache store that doesn't match the required interface" do
      class CachingExampleCacheStore2
        def write(key, value, options={}) ; end
        def fetch(key, &block) ; end
      end
      class CachingExampleCacheStore3
        def read(key) ; end
        def fetch(key, &block) ; end
      end
      class CachingExampleCacheStore4
        def read(key) ; end
        def write(key, value, options={}) ; end
      end

      expect{ Flexirest::Base.cache_store = CachingExampleCacheStore2.new }.to raise_error(Flexirest::InvalidCacheStoreException)
      expect{ Flexirest::Base.cache_store = CachingExampleCacheStore3.new }.to raise_error(Flexirest::InvalidCacheStoreException)
      expect{ Flexirest::Base.cache_store = CachingExampleCacheStore4.new }.to raise_error(Flexirest::InvalidCacheStoreException)
    end

    it "should allow you to remove the custom cache store" do
      expect{ Flexirest::Base.cache_store = nil }.to_not raise_error
    end
  end

  context "Reading/writing to the cache" do
    before :each do
      Object.send(:remove_const, :CachingExampleCacheStore5) if defined?(CachingExampleCacheStore5)
      class CachingExampleCacheStore5
        def read(key) ; end
        def write(key, value, options={}) ; end
        def fetch(key, &block) ; end
      end

      class Person < Flexirest::Base
        perform_caching true
        base_url "http://www.example.com"
        get :all, "/"
        put :save_all, "/"
      end

      Person.cache_store = CachingExampleCacheStore5.new

      @cache_control = "public, max-age=30"
      @etag = "6527914a91e0c5769f6de281f25bd891"
      @cached_object = Person.new(first_name:"Johnny")
    end

    it "should read from the cache store, to check for an etag" do
      headers = {
        Rack::ETAG => @etag
      }
      cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(Marshal.dump(cached_response))
      expect_any_instance_of(Flexirest::Connection).to receive(:get){ |connection, path, options|
        expect(path).to eq('/')
        expect(options[:headers]).to include("If-None-Match" => @etag)
      }.and_return(::FaradayResponseMock.new(OpenStruct.new(status:304, response_headers:{})))
      ret = Person.all
      expect(ret.first_name).to eq("Johnny")
    end

    it "should not read from the cache store to check for an etag unless it's a GET request" do
      headers = {
        Rack::ETAG => @etag,
        Rack::EXPIRES => (Time.now + 30).httpdate
      }
      cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
      expect_any_instance_of(CachingExampleCacheStore5).to_not receive(:read)
      expect_any_instance_of(Flexirest::Connection).to receive(:put).and_return(::FaradayResponseMock.new(OpenStruct.new(status:200, body: {result: "foo"}.to_json, response_headers:{})))
      ret = Person.save_all
    end

    it 'queries the server when the cache has expired via etag' do
      headers = {
        Rack::ETAG => @etag
      }
      cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
      allow_any_instance_of(CachingExampleCacheStore5).to receive(:read).and_return(Marshal.dump(cached_response))
      new_name = 'Pete'
      response_body = Person.new(first_name: new_name).to_json
      response = ::FaradayResponseMock.new(double(status: 200, response_headers: {}, body: response_body))
      allow_any_instance_of(Flexirest::Connection).to(
        receive(:get){ |connection, path, options|
          expect(path).to eq('/')
          expect(options[:headers]).to include('If-None-Match' => @etag)
        }.and_return(response))

      result = Person.all

      expect(result.first_name).to eq new_name
    end

    it 'queries the server when the cache has expired via cache-control' do
      headers = {
        Rack::CACHE_CONTROL => @cache_control,
        'Date' => (Time.now - 60).httpdate
      }
      cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
      allow_any_instance_of(CachingExampleCacheStore5).to receive(:read).and_return(Marshal.dump(cached_response))
      new_name = 'Pete'
      response_body = Person.new(first_name: new_name).to_json
      response = ::FaradayResponseMock.new(double(status: 200, response_headers: {}, body: response_body))
      allow_any_instance_of(Flexirest::Connection).to(
        receive(:get){ |connection, path, options|
          expect(path).to eq('/')
        }.and_return(response))

      result = Person.all

      expect(result.first_name).to eq new_name
    end

    it "should read from the cache store, and not call the server if there's a valid cache-control" do
       headers = {
         Rack::CACHE_CONTROL => @cache_control,
         'Date' => Time.now.httpdate
       }
       cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
       expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(Marshal.dump(cached_response))
       expect_any_instance_of(Flexirest::Connection).not_to receive(:get)
       ret = Person.all
       expect(ret.first_name).to eq("Johnny")
    end

    it "should read from the cache store and restore to the same object in the case of cache-control" do
      headers = {
          Rack::CACHE_CONTROL => @cache_control,
          'Date' => Time.now.httpdate
      }
      cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(Marshal.dump(cached_response))
      expect_any_instance_of(Flexirest::Connection).not_to receive(:get)
      p = Person.new(first_name:"Billy")
      ret = p.all({})
      expect(ret.first_name).to eq("Johnny")
    end

    it "should restore a result iterator from the cache store, if there's a cache-control" do
      class CachingExample3 < Flexirest::Base ; end
      object = Flexirest::ResultIterator.new(double(status: 200))
      object << CachingExample3.new(first_name:"Johnny")
      object << CachingExample3.new(first_name:"Billy")
      etag = "6527914a91e0c5769f6de281f25bd891"
      cache_control = "public; max-age=30"
      headers = {
          Rack::CACHE_CONTROL => cache_control,
          'Date' => Time.now.httpdate,
          Rack::ETAG => etag,
          Rack::EXPIRES => (Time.now + 30).httpdate
      }
      cached_response = Rack::Cache::Response.new(200, headers, object.items.as_json)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(Marshal.dump(cached_response))
      expect_any_instance_of(Flexirest::Connection).not_to receive(:get)
      ret = Person.all
      expect(ret.first.first_name).to eq("Johnny")
      expect(ret._status).to eq(200)
    end

    it "should read from the cache store, and not call the server if there's a hard expiry" do
      headers = {
        Rack::EXPIRES => (Time.now + 30).httpdate
      }
      cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(Marshal.dump(cached_response))
      expect_any_instance_of(Flexirest::Connection).not_to receive(:get)
      ret = Person.all
      expect(ret.first_name).to eq("Johnny")
    end

    it "should read from the cache store and restore to the same object in the case of expires" do
      headers = {
          Rack::EXPIRES => (Time.now + 30).httpdate
      }
      cached_response = Rack::Cache::Response.new(200, headers, @cached_object.to_json)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(Marshal.dump(cached_response))
      expect_any_instance_of(Flexirest::Connection).not_to receive(:get)
      p = Person.new(first_name:"Billy")
      ret = p.all({})
      expect(ret.first_name).to eq("Johnny")
    end

    it "should restore a result iterator from the cache store, if there's a hard expiry" do
      class CachingExample3 < Flexirest::Base ; end
      object = Flexirest::ResultIterator.new(double(status: 200))
      object << CachingExample3.new(first_name:"Johnny")
      object << CachingExample3.new(first_name:"Billy")
      etag = "6527914a91e0c5769f6de281f25bd891"
      headers = {
          Rack::ETAG => etag,
          Rack::EXPIRES => (Time.now + 30).httpdate
      }
      cached_response = Rack::Cache::Response.new(200, headers, object.items.as_json)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(Marshal.dump(cached_response))
      expect_any_instance_of(Flexirest::Connection).not_to receive(:get)
      ret = Person.all
      expect(ret.first.first_name).to eq("Johnny")
      expect(ret._status).to eq(200)
    end

    it "should not write the response to the cache unless it has caching headers" do
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(nil)
      expect_any_instance_of(CachingExampleCacheStore5).not_to receive(:write)
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(OpenStruct.new(status:200, body:"{\"result\":true}", headers:{}))
      Person.all
    end

    it "should write the response to the cache if there's an etag" do
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(nil)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:write).once.with("Person:/", an_instance_of(String), {})
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(::FaradayResponseMock.new(OpenStruct.new(status:200, body:"{\"result\":true}", response_headers:{Rack::ETAG=>"1234567890"})))
      Person.perform_caching true
      Person.all
    end

    it "should not write the response to the cache if there's an etag but perform_caching is off" do
      expect(Person.cache_store).to_not receive(:read)
      expect(Person.cache_store).to_not receive(:write)
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(::FaradayResponseMock.new(OpenStruct.new(status:200, body:"{\"result\":true}", response_headers:{Rack::ETAG=>"1234567890"})))
      Person.perform_caching false
      Person.all
    end

    it "should not write the response to the cache if there's an etag but perform_caching is off at the base level" do
      begin
        caching = Flexirest::Base.perform_caching
        Flexirest::Base.perform_caching false
        Person._reset_caching!
        Person.cache_store = CachingExampleCacheStore5.new
        expect(Person.cache_store).to_not receive(:read)
        expect(Person.cache_store).to_not receive(:write)
        expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(::FaradayResponseMock.new(OpenStruct.new(status:200, body:"{\"result\":true}", response_headers:{Rack::ETAG=>"1234567890"})))
        Person.all
      ensure
        Flexirest::Base.perform_caching caching
      end
    end

    it "should write the response to the cache if there's a valid cache-control" do
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(nil)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:write).once.with("Person:/", an_instance_of(String), an_instance_of(Hash))
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(::FaradayResponseMock.new(OpenStruct.new(status:200, body:"{\"result\":true}", response_headers:{Rack::CACHE_CONTROL=>"public, max-age=30"})))
      Person.perform_caching = true
      Person.all
    end

    it "should not write the response to the cache if there's an invalid cache-control" do
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(nil)
      expect_any_instance_of(CachingExampleCacheStore5).to_not receive(:write).once.with("Person:/", an_instance_of(String), an_instance_of(Hash))
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(OpenStruct.new(status:200, body:"{\"result\":true}", headers:{Rack::CACHE_CONTROL=>"public, max-age=0"}))
      Person.perform_caching = true
      Person.all
    end

    it "should not write the response to the cache if there's a no-store value for cache-control" do
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(nil)
      expect_any_instance_of(CachingExampleCacheStore5).to_not receive(:write).once.with("Person:/", an_instance_of(String), an_instance_of(Hash))
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(OpenStruct.new(status:200, body:"{\"result\":true}", headers:{Rack::CACHE_CONTROL=>"no-store"}))
      Person.perform_caching = true
      Person.all
    end

    it "should write the response to the cache if there's a hard expiry" do
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(nil)
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:write).once.with("Person:/", an_instance_of(String), an_instance_of(Hash))
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(::FaradayResponseMock.new(OpenStruct.new(status:200, body:"{\"result\":true}", response_headers:{Rack::EXPIRES=>(Time.now + 30).httpdate})))
      Person.perform_caching = true
      Person.all
    end

    it "should not write the response to the cache if there's an invalid expiry" do
      expect_any_instance_of(CachingExampleCacheStore5).to receive(:read).once.with("Person:/").and_return(nil)
      expect_any_instance_of(CachingExampleCacheStore5).to_not receive(:write).once.with("Person:/", an_instance_of(String), an_instance_of(Hash))
      expect_any_instance_of(Flexirest::Connection).to receive(:get).with("/", an_instance_of(Hash)).and_return(OpenStruct.new(status:200, body:"{\"result\":true}", headers:{Rack::EXPIRES=>"0"}))
      Person.perform_caching = true
      Person.all
    end

  end

end
