alias AOS.Constants.General
alias AOS.Seeds

General.current_env() |> Seeds.seed_entities()
