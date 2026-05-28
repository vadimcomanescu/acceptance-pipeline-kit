# mutation-stamp: sha256=023fe7ccbe94a367bd834046a3416d9efb8c7a8628c681f6a00b1412422c6cec
# acceptance-mutation-manifest-begin
# {"version":1,"tested_at":"2026-05-28T16:11:00Z","feature_name":"Calculator","feature_path":"features/calculator.feature","background_hash":"f36622cb93f814bc6de2581b884b7be204e5469a856e253554be8c6d1484b743","implementation_hash":"sha256:31fca1d3769a9c68a7b8a8a76725bd74c88e1b5553997c1ec516477cec4a7c6f","scenarios":[{"index":0,"name":"addition","scenario_hash":"5ed73fb09de0063e3bc738370297243ac1bc6efa08640376920a6aa7a22da409","mutation_count":9,"result":{"Total":9,"Killed":9,"Survived":0,"Errors":0},"tested_at":"2026-05-28T16:11:00Z"},{"index":1,"name":"subtraction","scenario_hash":"5f845c34e054fec4f5168911737bf13fa9dfdae7d2781ec20eb84fc062a6343e","mutation_count":6,"result":{"Total":6,"Killed":6,"Survived":0,"Errors":0},"tested_at":"2026-05-28T16:11:00Z"}]}
# acceptance-mutation-manifest-end

Feature: Calculator

  Background:
    Given a fresh calculator

  Scenario Outline: addition
    When I add <a> and <b>
    Then the result is <sum>

    Examples:
      | a | b | sum |
      | 1 | 2 | 3   |
      | 4 | 5 | 9   |
      | 0 | 0 | 0   |

  Scenario Outline: subtraction
    When I subtract <b> from <a>
    Then the result is <diff>

    Examples:
      | a  | b | diff |
      | 10 | 3 | 7    |
      | 5  | 5 | 0    |
