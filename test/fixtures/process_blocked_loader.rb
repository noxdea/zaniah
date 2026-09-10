# frozen_string_literal: true

Signal.trap("TERM", "IGNORE")
loop { sleep 1 }
