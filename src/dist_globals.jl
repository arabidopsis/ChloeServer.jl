import Logging
const LOGLEVELS =
    Dict("info" => Logging.Info, "debug" => Logging.Debug, "warn" => Logging.Warn, "error" => Logging.Error)

const ZMQ_WORKER = "tcp://127.0.0.1:9459"
const ZMQ_ENDPOINT = "ipc:///tmp/chloe6-client"
const ZMQ_BACKEND = "ipc:///tmp/chloe6-backend"
# change this if you change the API!
const VERSION = "6.0"
