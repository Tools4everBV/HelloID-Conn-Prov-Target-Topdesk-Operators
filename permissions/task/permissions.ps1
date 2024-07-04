###################################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Permissions-Tasks
# PowerShell V2
#####################################################

$prefixeName = "Task "

$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "installer"
        Identification = @{
            Reference = "installer"
            Name      = $prefixeName + "installer"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "first line call operator"
        Identification = @{
            Reference = "firstLineCallOperator"
            Name      = $prefixeName + "first line call operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "second line call operator"
        Identification = @{
            Reference = "secondLineCallOperator"
            Name      = $prefixeName + "second line call operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "problem manager"
        Identification = @{
            Reference = "problemManager"
            Name      = $prefixeName + "problem manager"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "problem operator"
        Identification = @{
            Reference = "problemOperator"
            Name      = $prefixeName + "problem operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "change coordinator"
        Identification = @{
            Reference = "changeCoordinator"
            Name      = $prefixeName + "change coordinator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "change activities operator"
        Identification = @{
            Reference = "changeActivitiesOperator"
            Name      = $prefixeName + "change activities operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "request for change operator"
        Identification = @{
            Reference = "requestForChangeOperator"
            Name      = $prefixeName + "request for change operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "extensive change operator"
        Identification = @{
            Reference = "extensiveChangeOperator"
            Name      = $prefixeName + "extensive change operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "simple change operator"
        Identification = @{
            Reference = "simpleChangeOperator"
            Name      = $prefixeName + "simple change operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "scenario manager"
        Identification = @{
            Reference = "scenarioManager"
            Name      = $prefixeName + "scenario manager"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "planning activity manager"
        Identification = @{
            Reference = "planningActivityManager"
            Name      = $prefixeName + "planning activity manager"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "project coordinator"
        Identification = @{
            Reference = "projectCoordinator"
            Name      = $prefixeName + "project coordinator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "project activies operator"
        Identification = @{
            Reference = "projectActiviesOperator"
            Name      = $prefixeName + "project activies operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "stock manager"
        Identification = @{
            Reference = "stockManager"
            Name      = $prefixeName + "stock manager"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "reservations operator"
        Identification = @{
            Reference = "reservationsOperator"
            Name      = $prefixeName + "reservations operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "service operator"
        Identification = @{
            Reference = "serviceOperator"
            Name      = $prefixeName + "service operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "external help desk party"
        Identification = @{
            Reference = "externalHelpDeskParty"
            Name      = $prefixeName + "external help desk party"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "contract manager"
        Identification = @{
            Reference = "contractManager"
            Name      = $prefixeName + "contract manager"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "operations operator"
        Identification = @{
            Reference = "operationsOperator"
            Name      = $prefixeName + "operations operator"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "operations manager"
        Identification = @{
            Reference = "operationsManager"
            Name      = $prefixeName + "operations manager"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "knowledge base manager"
        Identification = @{
            Reference = "knowledgeBaseManager"
            Name      = $prefixeName + "knowledge base manager"
            Type      = "Task"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "account manager"
        Identification = @{
            Reference = "accountManager"
            Name      = $prefixeName + "account manager"
            Type      = "Task"
        }
    }
)