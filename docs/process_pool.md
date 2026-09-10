# CPU process workers

`ProcessPool` runs trusted CPU work in reusable Ruby child processes. For
portable spawning, put the handler in a loadable file and expose `.call(data)`:

```ruby
# /absolute/path/word_count.rb
module WordCount
  def self.call(data)
    {"words" => data.fetch("text").split.length}
  end
end
```

```ruby
require "zaniah"
require "zaniah/process_pool"

pool = Zaniah::ProcessPool.new(
  workers: 2,
  handler: "WordCount",
  requires: [File.expand_path("word_count.rb")],
  max_pending: 4
)

task = pool.submit("text" => "Hello Ruby")
result = task.await(timeout: 2)
pool.shutdown
```

`requires:` accepts existing absolute Ruby filenames and `load_paths:` accepts
absolute directories. Workers start lazily, may keep process-local caches, and
do not guarantee that related requests use the same process. Failed workers are
replaced; lost work is not replayed.

## Data and limits

Arguments and results must be plain JSON values: nil, booleans, integers, finite
floats, valid UTF-8 strings, arrays, and string-keyed hashes. Values are copied
at submission and received values are frozen. Custom objects, symbols, cycles,
excessive nesting, and invalid strings are rejected.

The default message limit is 16 MiB. `workers:` accepts 1–32 and `max_pending:`
defaults to twice the worker count. Submitting to a full or shut-down pool raises
`Zaniah::Error` immediately. Handlers are application code: the pool is not a
sandbox for untrusted Ruby.

## Cancellation and cleanup

`Task#cancel` cancels queued work or terminates the child running that task. An
`await` timeout does not cancel work, so call `cancel` when abandoning a task.
Cancellation cannot undo external side effects already performed by a handler.

`shutdown(timeout: 2)` rejects new submissions, cancels outstanding tasks, and
cleans up workers. It is idempotent. If cleanup misses the deadline it raises
`Task::Timeout`, and shutdown may be retried.

The block form remains available on platforms with `fork`, but named handlers
are preferred for portability and for applications that own threads or native
resources. Both forms use the same JSON-only data contract.

See [the RBS declarations](../sig/app.rbs) for the complete API. Run the worker
tests with:

```sh
ruby -Itest test/process_pool_test.rb
```
