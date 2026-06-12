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
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "first line call operator"
        Identification = @{
            Reference = "firstLineCallOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "second line call operator"
        Identification = @{
            Reference = "secondLineCallOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "problem manager"
        Identification = @{
            Reference = "problemManager"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "problem operator"
        Identification = @{
            Reference = "problemOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "change coordinator"
        Identification = @{
            Reference = "changeCoordinator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "change activities operator"
        Identification = @{
            Reference = "changeActivitiesOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "request for change operator"
        Identification = @{
            Reference = "requestForChangeOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "extensive change operator"
        Identification = @{
            Reference = "extensiveChangeOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "simple change operator"
        Identification = @{
            Reference = "simpleChangeOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "scenario manager"
        Identification = @{
            Reference = "scenarioManager"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "planning activity manager"
        Identification = @{
            Reference = "planningActivityManager"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "project coordinator"
        Identification = @{
            Reference = "projectCoordinator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "project activies operator"
        Identification = @{
            Reference = "projectActiviesOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "stock manager"
        Identification = @{
            Reference = "stockManager"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "reservations operator"
        Identification = @{
            Reference = "reservationsOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "service operator"
        Identification = @{
            Reference = "serviceOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "external help desk party"
        Identification = @{
            Reference = "externalHelpDeskParty"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "contract manager"
        Identification = @{
            Reference = "contractManager"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "operations operator"
        Identification = @{
            Reference = "operationsOperator"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "operations manager"
        Identification = @{
            Reference = "operationsManager"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "knowledge base manager"
        Identification = @{
            Reference = "knowledgeBaseManager"
        }
    }
)
$outputContext.Permissions.Add(
    @{
        DisplayName    = $prefixeName + "account manager"
        Identification = @{
            Reference = "accountManager"
        }
    }
)