# Common configuration of the firmware (DES15); imports host.exs or target.exs.
import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

# Fixed date for reproducible builds (https://reproducible-builds.org/docs/source-date-epoch/)
config :nerves, source_date_epoch: "1763683200"

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
