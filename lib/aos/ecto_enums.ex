# Define all enums specifically for Ecto.

import EctoEnum

require AOS.Enums

defenum(
  AOS.EnvironmentEnum,
  :environment_enum,
  AOS.Enums.environment_const()
)
