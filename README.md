# CoreDataConnector::OpenGeographies

Short description and motivation.

## Usage

How to use my plugin.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "core_data_connector_open_geographies"
```

And then execute:

```bash
$ bundle
```

Or install it yourself as:

```bash
$ gem install core_data_connector_open_geographies
```

## Running Tests

Install/update migrations from CoreDataConnector

```bash
cd spec/dummy && \
bundle exec rails core_data_connector:install:migrations && \
bundle exec rails user_defined_fields:install:migrations && \
bundle exec rails fuzzy_dates:install:migrations && \
bundle exec rails triple_eye_effable:install:migrations && \
cd ../..
```

To run the tests:

```bash
bundle exec rspec spec/geojson.spec
```

## Contributing

Contribution directions go here.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
