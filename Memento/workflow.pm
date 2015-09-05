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
    $op = Daemon::prompt("Choose an operation", undef, ['add', 'edit', 'delete', 'list']);
  }

  switch ($op) {
    case 'add' {
      # Handle Event.
      $class->_get_all_events(\my $all_events);
      my $avail_events = [];
      my %events_list;

      foreach my $event (@{$all_events}) {
        $events_list{$event->{name}} = $event;
        push(@{$avail_events}, $event->{name});
      }

      my $event_name = Daemon::prompt("Choose an event", undef, $avail_events);
      my $event = $events_list{$event_name};

      # Handle Conditions.
      my $conditions = [];
      $class->_get_all_conditions(\my $all_conditions);
      my $avail_conditions = $class->_get_allowed_event_interaction('conditions', {interactions => $all_conditions, event => $event}, \my %conditions_list);

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
            my $tool = MemenTool->instantiate($condition->{tool}, '');
            my $options_callback = $param->{options};
            my $options = $options_callback ? $tool->$options_callback() : undef;
            $condition_rule->{params}->{$param->{name}} = Daemon::prompt("Enter $param->{label}", undef, $options);
          }
        }

        push(@{$conditions}, $condition_rule);
      }

      # Handle Actions.
      my $actions = [];
      $class->_get_all_actions(\my $all_actions);
      my $avail_actions = $class->_get_allowed_event_interaction('events', {interactions => $all_actions, event => $event}, \my %actions_list);
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
            my $tool = MemenTool->instantiate($action->{tool}, '');
            my $options_callback = $param->{options};
            my $options = $options_callback ? $tool->$options_callback() : undef;
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
      say "Workflow Rule $rule_name has been saved";
    }
    case 'edit' {
      my $name = Daemon::prompt("Enter the Workflow Rule to edit", undef, $class->_get_rules());
      my $rule = $class->_get_rule($name);
      my $filename = "/tmp/memento-workflow-rule-$name";

      Daemon::write($filename, JSON::PP->new->utf8->pretty->encode($rule), '1', '>');
      Daemon::open_default_editor($filename);
      my $edit_rule = Daemon::json_decode_file($filename);
      unlink $filename;

      $class->_delete_rule($name);
      $config = $class->_get_config();
      push(@{$config->{rules}}, $edit_rule);
      $class->_save_config($config);
    }
    case 'list' {
      say Daemon::array2table("Workflow Rules", $config->{rules}, {full_nested => 1});
    }
    case 'delete' {
      my $name = Daemon::prompt("Enter the Workflow Rule to delete", undef, $class->_get_rules());
      $class->_delete_rule($name);
      say "Workflow Rule $name have been deleted";
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
  $class = MemenTool->instantiate($tool_name, '');

  my $item = shift;
  my $event = shift;
  my $config = $class->_get_config();
  my $rules = $config->{rules};
  my @arguments = $_[0][0] || [];

  foreach my $rule (@{$rules}) {
    # Checks event.
    if ($event eq "_on_" . $rule->{event}) {

      # Checks conditions
      my $count_valid = 0;
      foreach my $condition (@{$rule->{conditions}}) {
        my $tool = MemenTool->instantiate($condition->{tool}, '');
        my $callback = $condition->{callback};
        my $params = $condition->{params} ? $condition->{params} : {};

        if ($tool->can($callback) && $tool->$callback($params)) {
          $count_valid++;
        }
      }

      # Executes actions
      if ($count_valid == scalar(@{$rule->{conditions}})) {
        foreach my $action (@{$rule->{actions}}) {
          my $tool = MemenTool->instantiate($action->{tool}, '');
          my $callback = $action->{callback};
          my $params = $action->{params} ? $action->{params} : {};

          if ($tool->can($callback)) {
            $tool->$callback($arguments[0], $params);
          }
        }
      }
    }
  }
}

# PRIVATE METHODS ##############################################################

sub _get_all_events {
  my $class = shift;
  my $events = shift;
  my @commands = MemenTool->commands();
  foreach my $tool (@commands) {
    $tool = MemenTool->instantiate($tool, '');
    foreach my $event (@{$tool->_events()}) {
      push(@{${$events}}, $event);
    }
  }

  return $events;
}

sub _get_all_conditions {
  my $class = shift;
  my $conditions = shift;
  my @commands = MemenTool->commands();
  foreach my $tool (@commands) {
    $tool = MemenTool->instantiate($tool, '');
    foreach my $condition (@{$tool->_conditions()}) {
      push(@{${$conditions}}, $condition);
    }
  }

  return $conditions;
}

sub _get_all_actions {
  my $class = shift;
  my $actions = shift;
  my @commands = MemenTool->commands();
  foreach my $tool (@commands) {
    $tool = MemenTool->instantiate($tool, '');
    foreach my $action (@{$tool->_actions()}) {
      push(@{${$actions}}, $action);
    }
  }

  return $actions;
}

sub _get_allowed_event_interaction {
  my $class = shift;
  my $type = shift;
  my $params = shift;
  my $interactions_list = shift;

  my @interactions = @{$params->{interactions}};
  my $event = $params->{event};
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

      if ($avail_args >= scalar(@{$interaction->{arguments}})) {
        push(@{$avail_interactions}, $interaction->{name});
      }
    }
  }

  return $avail_interactions;
}

sub _get_rules {
  my $class = shift;
  my $config = $class->_get_config();
  my $rules;

  foreach my $rule (@{$config->{rules}}) {
    push(@{$rules}, $rule->{name});
  }

  return $rules;
}

sub _get_rule {
  my $class = shift;
  my $name = shift;
  my $config = $class->_get_config();
  my $i = 0;
  my $rule;

  for my $item (@{$config->{rules}}) {
    if ($item->{name} eq $name) {
      $rule = $config->{rules}[$i];
    }
    $i++;
  }

  if ($rule) {
    return $rule;
  }
  else {
    die "Cannot find workflow rule $name\n";
  }
}

sub _delete_rule {
  my $class = shift;
  my $name = shift;

  if (!$class->_get_rule($name)) {
    die "Cannot delete workflow rule $name: rule not found.\n";
  }

  my $config = $class->_get_config();
  my $i = 0;
  for my $item (@{$config->{rules}}) {
    if ($item->{name} eq $name) {
      delete $config->{rules}[$i];
    }
    $i++;
  }

  $class->_save_config($config);
}

1;