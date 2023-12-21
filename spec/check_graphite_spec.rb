require 'rspec'
require 'webmock/rspec'

require 'check_graphite'

describe CheckGraphite::Command do

  before do 
    subject { CheckGraphite::Command.new }
    # allow($stdout).to receive(:puts)
  end

  describe 'it should make http requests and return data' do
    before do
      stub_request(:get, /your.graphite.host/).to_return(
        body: '[{"target": "default.test.boottime", "datapoints": [[1.0, 1339512060], [2.0, 1339512120], [6.0, 1339512180], [7.0, 1339512240]]}]',
        headers: {
          content_type: 'application/json',
        },
      )
    end

    it 'should return OK' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm])
      expect { subject.run }.to raise_error(SystemExit).and output("OK: value=4.0|value=4.0;;;;\n").to_stdout
    end

    it 'should return WARNING' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm -w 0])
      expect { subject.run }.to raise_error(SystemExit).and output("WARNING: value=4.0|value=4.0;;;;\n").to_stdout
    end

    it 'should return CRITICAL' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm -c 0])
      expect { subject.run }.to raise_error(SystemExit).and output("CRITICAL: value=4.0|value=4.0;;;;\n").to_stdout
    end

    it 'should honour dropfirst' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm --dropfirst 1])
      expect { subject.run }.to raise_error(SystemExit).and output("OK: value=5.0|value=5.0;;;;\n").to_stdout
    end

    it 'should honour droplast' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm --droplast 1])
      expect { subject.run }.to raise_error(SystemExit).and output("OK: value=3.0|value=3.0;;;;\n").to_stdout
    end

    it 'should honour dropfirst and droplast together' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm --dropfirst 1 --droplast 1])
      expect { subject.run }.to raise_error(SystemExit).and output("OK: value=4.0|value=4.0;;;;\n").to_stdout

    end
  end

  describe 'when data contains null values' do
    before do
      stub_request(:get, /your.graphite.host/).to_return(
        body: '[{"target": "default.test.boottime", "datapoints": [[5.0, 1339512060], [null, 1339512120], [null, 1339512180], [3.0, 1339512240]]}]',
        headers: {
          content_type: 'application/json',
        },
      )
    end

    it 'should discard them' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm])
      expect { subject.run }.to raise_error(SystemExit).and output("OK: value=4.0|value=4.0;;;;\n").to_stdout
    end
  end

  describe 'when Graphite returns no data at all' do
    before do
      stub_request(:get, /your.graphite.host/).with(
        query: hash_including({ target: 'value.does.not.exist' }),
      ).to_return(
        body: '[]',
        headers: {
          content_type: 'application/json',
        },
      )
    end

    it 'should be unknown' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M value.does.not.exist])
      expect { subject.run }.to raise_error(SystemExit).and output(/UNKNOWN: INTERNAL ERROR: (RuntimeError: )?no data returned for target/).to_stdout
    end

    it 'should be ok when ignoring missing data' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M value.does.not.exist --ignore-missing -w 1 -c 3])
      expect { subject.run }.to raise_error(SystemExit).and output(/OK: value missing - ignoring/).to_stdout

    end
  end

  describe 'when Graphite returns only NULL values' do
    before do
      stub_request(:get, /your.graphite.host/).with(
        query: hash_including({ target: 'all.values.null' })
      ).to_return(
        {
          body: '[{"target": "all.values.null", "datapoints": [[null, 1339512060], [null, 1339512120], [null, 1339512180], [null, 1339512240]]}]',
          headers: {
            content_type: 'application/json',
          }
        }
      )
    end

    it 'should be unknown' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M all.values.null])
      expect { subject.run }.to raise_error(SystemExit).and output(/UNKNOWN: INTERNAL ERROR: (RuntimeError: )?no valid datapoints/).to_stdout
    end
  end

  describe 'when Graphite returns multiple targets' do
    before do
      stub_request(:get, /your.graphite.host/).with(
        query: hash_including({ target: 'collectd.*.load.load.midterm' })
      ).to_return(
        {
          body: '[{"target": "collectd.somebox.load.load.midterm", "datapoints": [[null, 1339512060], [null, 1339512120], [null, 1339512180], [null, 1339512240]]},{"target": "collectd.somebox1.load.load.midterm", "datapoints": [[1.0, 1339512060], [2.0, 1339512120], [6.0, 1339512180], [7.0, 1339512240]]}]',
          headers: {
            content_type: 'application/json',
          }
        }
      )
    end

    it 'should return OK' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.*.load.load.midterm])
      expect { subject.run }.to raise_error(SystemExit).and output("OK: value=4.0|value=4.0;;;;\n").to_stdout
    end
  end

  describe 'it should make http requests with basic auth and return data' do
    before do
      stub_request(
        :get, /your.graphite.host/
      ).with(
        basic_auth: ['testuser', 'testpass'],
        query: {
          target: 'collectd.somebox.load.load.midterm',
          from: '-30seconds',
          format: 'json',
        },
      ).to_return(
        body: '[{"target": "default.test.boottime", "datapoints": [[1.0, 1339512060], [3.0, 1339512120]]}]',
        headers: {
          content_type: 'application/json',
        },
      )
      stub_request(
        :get, /your.graphite.host/
      ).with(
        basic_auth: ['baduser', 'badpass'],
        query: {
          target: 'collectd.somebox.load.load.midterm',
          from: '-30seconds',
          format: 'json',
        },
      ).to_return(
        status: 401,
        body: 'Unauthorized',
        headers: {
          status: ['401', 'Unauthorized'],
          content_type: 'application/json',
        },
      )
    end

    it 'should work with valid username and password' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm -U testuser -P testpass])
      expect { subject.run }.to raise_error(SystemExit).and output("OK: value=2.0|value=2.0;;;;\n").to_stdout
    end

    it 'should fail with bad username and password' do
      stub_const('ARGV', %w[-H http://your.graphite.host/render -M collectd.somebox.load.load.midterm -U baduser -P badpass])
      expect { subject.run }.to raise_error(SystemExit).and output(/UNKNOWN: INTERNAL ERROR: (RuntimeError: )?HTTP error code 401/).to_stdout
    end
  end
end
