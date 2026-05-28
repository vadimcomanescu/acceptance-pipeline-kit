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
