# PBS Ruby

## Description

Trimmed down Ruby wrapper for the Torque C Library utilizing Ruby-FFI.

## Requirements

At minimum you will need:
* Ruby 2.0
* Ruby-FFI gem
* Torque >= 4.2.10

## Installation

Add this to your application's Gemfile:

```ruby
  gem 'pbs'
```

And then execute:

```bash
  $ bundle install
```

## Usage

Most useful features are outlined in the `examples/simplejob.rb` provided. To run this simple example, type:

```bash
  $ ruby -Ilib examples/simplejob.rb
```
