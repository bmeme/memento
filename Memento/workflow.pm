#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Command.pm";
our ($root);

package Memento::workflow;

use feature 'say';
our @ISA = qw(Command);
use strict; use warnings;
use Switch;
use Data::Dumper;

sub rules {
  my $class = shift;
  my $op = shift;
  my $config = $class->_get_config();

  if (!$op) {
    $op = Daemon::prompt("Choose an operation", undef, ['add', 'delete', 'list']);
  }

  switch ($op) {
    case 'add' {
      # Handle Event.
      my $all_events = $class->_get_all_events();
      my $avail_events = [];
      my %events_list;

      foreach my $event (@{$all_events}) {
        $events_list{$event->{name}} = $event;
        push(@{$avail_events}, $event->{name});
      }

      my $event_name = Daemon::prompt("Choose an event", undef, $avail_events);

      # Handle Conditions.
      my $conditions = [];
      my $avail_conditions = $class->_get_allowed_event_interaction(@{$class->_get_all_conditions()}, $events_list{$event_name}, \my %conditions_list);

      while (Daemon::prompt("Do you need to add a condition?", 'no', ['yes', 'no']) eq 'yes') {
        my $condition_name = Daemon::prompt('Choose a condition', undef, $avail_conditions);
        my $condition = $conditions_list{$condition_name};
        my $condition_rule = {
          tool => $condition->{tool},
          callback => $condition->{callback},
          params => {}
        };

        if ($condition->{params}) {
          foreach my $param (@{$condition->{params}}) {
            my $tool = Memento->instantiate($condition->{tool}, '');
            my $options_callback = $param->{options};
            my $options = $options_callback ? $tool->$options_callback() : undef;
            $condition_rule->{params}->{$param->{name}} = Daemon::prompt("Enter $param->{label}", undef, $options);
          }
        }

        push(@{$conditions}, $condition_rule);
      }

      # Handle Actions.
      my $actions = [];
      my $avail_actions = $class->_get_allowed_event_interaction(@{$class->_get_all_actions()}, $events_list{$event_name}, \my %actions_list);

      do {
        my $action_name = Daemon::prompt("Choose an action", undef, $avail_actions);
        my $action = $actions_list{$action_name};
        my $action_rule = {
          tool => $action->{tool},
          callback => $action->{callback},
          params => {}
        };

        if ($action->{params}) {
          foreach my $param (@{$action->{params}}) {
            my $tool = Memento->instantiate($action->{tool}, '');
            my $options_callback = $param->{options};
            my $options = $options_callback ? $tool->$options_callback() : [];
            $action_rule->{params}->{$param->{name}} = Daemon::prompt("Enter $param->{label}", undef, $options);
          }
        }

        push(@{$actions}, $action_rule);
      } while (Daemon::prompt("Do you want to add another action?", 'no', ['yes', 'no']) eq 'yes');

      say "Rule configuration finished!";
      my $rule_label = Daemon::prompt("Provide a label for this Workflow Rule");
      my $rule_name = Daemon::machine_name($rule_label);

      # Create the rule.
      my $rule = {
        name => $rule_name,
        label => $rule_label,
        event => $event_name,
        conditions => $conditions,
        actions => $actions
      };

      push(@{$config->{rules}}, $rule);
      $class->_save_config($config);
      say 'Workflow Rule configurations have been saved';
    }
    case 'list' {
      say Daemon::array2table("Workflow Rules", $config->{rules});
    }
    case 'delete' {
      my $rules;
      foreach my $rule (@{$config->{rules}}) {
        push(@{$rules}, $rule->{name});
      }

      my $name = Daemon::prompt("Enter the Workflow Rule to delete", undef, $rules);
      my $i = 0;
      for my $item (@{$config->{rules}}) {
        if ($item->{name} eq $name) {
          delete $config->{rules}[$i];
        }
        $i++;
      }

      $class->_save_config($config);
      say 'Workflow API configurations have been deleted';
    }
  }
}

# OVERRIDDEN METHODS ###########################################################

sub _def_config {
  return {
    rules => []
  };
}

sub update {
  my $class = shift;
  my $tool_name = $class;
  $tool_name =~ s/^Memento\:\://;
  $class = Memento->instantiate($tool_name, '');

  my $item = shift;
  my $event = shift;
  my $config = $class->_get_config();
  my $rules = $config->{rules};
  my @arguments = @_;

  foreach my $rule (@{$rules}) {
    # Checks event.
    if ($event eq "_on_" . $rule->{event}) {

      # Checks conditions
      my $count_valid = 0;
      foreach my $condition (@{$rule->{conditions}}) {
        my $tool = Memento->instantiate($condition->{tool}, '');
        my $callback = $condition->{callback};
        my $params = $condition->{params} ? $condition->{params} : {};

        if ($tool->can($callback) && $tool->$callback($params)) {
          $count_valid++;
        }
      }

      # Executes actions
      if ($count_valid == scalar(@{$rule->{conditions}})) {
        foreach my $action (@{$rule->{actions}}) {
          my $tool = Memento->instantiate($action->{tool}, '');
          my $callback = $action->{callback};
          my $params = $action->{params} ? $action->{params} : {};

          if ($tool->can($callback)) {
            $tool->$callback(@arguments, $params);
          }
        }
      }
    }
  }
}

# PRIVATE METHODS ##############################################################

sub _get_all_events {
  my @commands = Memento->commands();
  my $events = [];
  foreach my $tool (@commands) {
    $tool = Memento->instantiate($tool, '');
    foreach my $event (@{$tool->_events()}) {
      push(@{$events}, $event);
    }
  }

  return $events;
}

sub _get_all_conditions {
  my @commands = Memento->commands();
  my $conditions = [];
  foreach my $tool (@commands) {
    $tool = Memento->instantiate($tool, '');
    foreach my $condition (@{$tool->_conditions()}) {
      push(@{$conditions}, $condition);
    }
  }

  return $conditions;
}

sub _get_all_actions {
  my @commands = Memento->commands();
  my $actions = [];
  foreach my $tool (@commands) {
    $tool = Memento->instantiate($tool, '');
    foreach my $action (@{$tool->_actions()}) {
      push(@{$actions}, $action);
    }
  }

  return $actions;
}

sub _get_allowed_event_interaction {
  my $class = shift;
  my @interactions = shift;
  my $event = shift;
  my $interactions_list = shift;
  my $avail_interactions = [];

  foreach my $interaction (@interactions) {
    $interactions_list->{$interaction->{name}} = $interaction;

    if (!$interaction->{arguments}) {
      push(@{$avail_interactions}, $interaction->{name});
    }
    else {
      my $avail_args = 0;
      foreach my $interaction_arg (@{$interaction->{arguments}}) {
        if (Daemon::in_array($event->{arguments}, $interaction_arg)) {
          $avail_args++;
        }
      }

      if ($avail_args == scalar(@{$interaction->{arguments}})) {
        push(@{$avail_interactions}, $interaction->{name});
      }
    }
  }

  return $avail_interactions;
}

1;