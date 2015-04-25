var fs = require("fs"),
    common = require("azure-common"),
    resourceManagement = require("azure-mgmt-resource"),
    path = require("path");
var argv = require('optimist').usage('node azure_crp_compute.js -r resourcegroup -t task  ')
    .demand(['r', 't'])
    .describe('r', 'resource group name')
    .describe('t', 'task name')
    .argv;
var parallelLimit = 10;
var RETRY = {
    "RETRY": "RETRY"
};
var ABORT = {
    "ABORT": "ABORT"
};
var api_version = "2014-12-01-preview";
var get_log_api_version = "2014-04-01-preview"
var _resultStr = [];
var _logStr = [];

function _result(str) {
    _resultStr.push(str);

}

function _log(str) {
    //_logStr.push(String(new Date().toISOString()) + "  " + str);
    console.log(str);
}



function addRetry(task, retries) {
    var retry = require('retry')
    return task.map(function(t) {
        return function(callback) {
            var operation = retry.operation({
                maxTimeout: 60 * 1000,
                retries: retries
            });
            operation.attempt(function(currentAttempt) {
                try {
                    t(function(err, msg) {
                        if (err == RETRY && operation.retry(err)) {
                            _log("Retry " + currentAttempt + ":" + msg);
                        }
                        else {
                            callback(err, msg);
                        }
                    });
                }
                catch (ex) {
                    callback(ABORT, _log(ex.stack));
                }
            });
        }
    });

}

var azureCommand = function(p, callback) {

    var docommand = function(docommandcb) {
        var exec = require('child_process').execFile;
        _log("excute command azure " + p.join(" "));
        exec("azure", p, function(err, stdout, stderr) {
            //_log(stdout);
            if (stderr)
                _log(stderr);
            if (stderr.indexOf("'group' is not an azure command") > -1 || stderr.indexOf("'resource' is not an azure command") > -1) {
                azureCommand(["config", "mode", "arm"], function(err, msg) {
                    if (!err)
                        docommandcb(RETRY, msg);
                    else
                        docommandcb(err, msg);
                });
                return;
            }
            if (stderr.indexOf("ENOMEM, not enough memory") > -1) {
                docommandcb(RETRY, "do command retry not enought memory " + JSON.stringify(p));
                return;
            }
            if (stderr.indexOf("gateway did not receive a response from") > -1) {
                docommandcb(RETRY, "do command retry not receive resposne " + JSON.stringify(p));
                return;
            }
            if (stderr.match(/^An error has occurred/)) {
                docommandcb(RETRY, "unknow error happens " + JSON.stringify(p));
                return;
            }
            docommandcb(err == null ? stderr : err, stdout + stderr);
            //TODO,fire retry event in some scenario
            //callback(RETRY,stdout+stderr)
            //Eg, server rejected the request because too many requests have been received for this subscription
        });
    };
    docommand = addRetry([docommand], 10)[0];
    docommand(callback);
};

var NatRule = {
    "name": "ssh",
    "properties": {
        "frontendIPConfiguration": {
            "id": "[variables('frontEndIPConfigID')]"
        },
        "backendIPConfiguration": {
            "id": "[variables('backEndIPConfigID')]"
        },
        "protocol": "TCP",
        "frontendPort": 22,
        "backendPort": 22,
        "enableFloatingIP": false
    }
}
var NatRuleRef = {
    "id": ""
}

var formatParameter = function(templatefile, paramters) {
    var templateData = JSON.parse(String(fs.readFileSync(templatefile)));
    var newParameter = {};
    paramters["NatRules"] = [];
    paramters["NatRulesRef"] = [];
    Object.keys(paramters).forEach(function(key) {

        if (key == "TcpEndPoints" || key == "UdpEndPoints") {
            var isTcp = key == "TcpEndPoints";
            var lbName = paramters["lbName"];
            var nicName = paramters["nicName"];
            paramters[key].split(",").forEach(function(p) {
                p = p.trim()
                frontport = p.split(":")[0];
                endport = p.split(":")[1];
                NatRule.properties.frontendIPConfiguration = {
                    "id": "/subscriptions/" + paramters.sid + "/resourceGroups/" + paramters.rgname + "/providers/Microsoft.Network/loadBalancers/" + lbName + "/frontendIPConfigurations/LBFE"
                };
                NatRule.properties.backendIPConfiguration.id = "/subscriptions/" + paramters.sid + "/resourceGroups/" + paramters.rgname + "/providers/Microsoft.Network/networkInterfaces/" + nicName + "/ipConfigurations/ipconfig1";
                NatRule.properties.protocol = isTcp ? "Tcp" : "Udp";
                NatRule.name = "NatRule-" + key + "-" + frontport;
                NatRule.properties.frontendPort = frontport;
                NatRule.properties.backendPort = endport;
                paramters["NatRules"].push(JSON.parse(JSON.stringify(NatRule)));
                NatRuleRef.id = "/subscriptions/" + paramters.sid + "/resourceGroups/" + paramters.rgname + "/providers/Microsoft.Network/loadBalancers/" + lbName + "/inboundNatRules/" + NatRule.name
                paramters["NatRulesRef"].push(JSON.parse(JSON.stringify(NatRuleRef)));
            });
        }

    });

    Object.keys(templateData.parameters).forEach(function(key) {

        if (paramters[key]) {
            newParameter[key] = {
                'value': paramters[key]
            };
        }
    });
    return JSON.stringify(newParameter);
};

var doDeploy = function(resourcegroup, templatefile, paramters, deployname, sid, finishedCallback) {
    paramters.sid = sid;
    paramters.rgname = resourcegroup;

    azureCommand(["group", "deployment", "create", "-s", paramters.StorageAccountName, "-g", resourcegroup, "-n", deployname.id, "-f", templatefile, "-p", formatParameter(templatefile, paramters)], finishedCallback);
};


var waitDeploymentSuccess = function(doDeployTask, id, resourcegroup, deploymentname, finishedCallback) {
    if (!deploymentname.id) {
        deploymentname.id = String((new Date).getTime()) + "deploy"
    }
    doAzureResourceManage(id, resourcegroup, "/deployments/" + deploymentname.id, "", "GET", get_log_api_version,
        function(err, msg) {
            if (err) {
                if (err.code == "DeploymentNotFound") {
                    doDeployTask(function(err, msg) {
                        if (err) {
                            finishedCallback(err, msg);
                            return;
                        }
                        finishedCallback(RETRY, "deployment not started, retry");
                    })
                }
                else {
                    finishedCallback(err, msg);
                }
                return;
            }

            var deploy = JSON.parse(msg);
            var provisioningState = deploy.properties.provisioningState;
            switch (provisioningState) {
                case "Accepted":
                case "Running":
                    finishedCallback(RETRY, "Running");
                    break;
                case "Succeeded":
                    finishedCallback(null, "Deploy  succeeded");
                    break;
                case "Failed":
                    _log("deployment failed  collect  log after 30 seconds");
                    setTimeout(function() {
                        azureCommand(["group", "log", "show", "-n", resourcegroup, "-d", deploymentname.id, "--json"],
                            function(err, msg) {
                                if (err) {
                                    finishedCallback(err, msg);
                                    return;
                                }
                                err_msg = ""
                                JSON.parse(msg).forEach(function(t) {
                                    if (t.properties.statusMessage)
                                        err_msg += JSON.stringify(t.properties.statusMessage)
                                })

                                if (err_msg.indexOf("NetworkingInternalOperationError") > -1) {
                                    deploymentname.id = null;
                                    _log("Failed " + err_msg)
                                    finishedCallback(RETRY, "Retry internal error");
                                }
                                else {
                                    finishedCallback(ABORT, "deployment failed " + err_msg);
                                }
                            });
                    }, 30000);
                    break;
                default:
                    finishedCallback(ABORT, "unknow stat:" + provisioningState);
            }
        });
};




var findResource = function(resourcegroup, type, propertyId, value, REFresource, finishedCallback) {
    var IPName = null;
    var command = ["resource", "list", "-g", resourcegroup, "--json"];
    if (type && type.length > 0)
        command = command.concat(["-r", type]);

    azureCommand(command,
        function(err, msg) {
            if (err) {
                finishedCallback(err, msg);
            }

            else {
                var domainnames = JSON.parse(msg);
                var query_task = domainnames.map(function(n) {
                    return function(callback) {
                        getResource(resourcegroup, n.name, n.type,
                            function(err, msg) {
                                if (err) {
                                    if (msg.indexOf("resource type could not be found") > -1)
                                        callback(null, msg);
                                    else
                                        callback(err, msg);
                                    return;
                                }
                                else {
                                    var o = msg;
                                    var properties = propertyId.split(":")
                                    for (var i = 0; i < properties.length; i++) {
                                        if (o[properties[i]]) {
                                            o = o[properties[i]];
                                        }
                                        else break;
                                    }
                                    if (o == value) {
                                        REFresource.push(JSON.parse(msg))
                                    }
                                }
                                callback(err, msg);
                            });
                    };

                });
                // query_task = addRetry(query_task);
                var async = require('async');
                async.parallelLimit(query_task, parallelLimit,
                    function(error, result) {
                        if (error) {
                            _log("Task Failed in findResource with error " + JSON.stringify(error));
                        }
                        //  if(result.result)
                        _log("find object  " + REFresource.length)
                        finishedCallback(error, result);
                    });

            }
        });
};

var waitResourceupdated = function(resourcegroup, name, type, finishedCallback) {

    getResource(resourcegroup, name, type, function(err, result) {
        if (err == RETRY) {
            finishedCallback(RETRY, result);
            return;
        }
        if (result.properties.provisioningState == "updating") {
            finishedCallback(RETRY, "wait for vm state to be succeeded");
        }
        else {
            finishedCallback(null, "vm provision finished " + result.properties.provisioningState);
        }
    });
};

var waitVMupdated = function(resourcegroup, vmname, finishedCallback) {
    waitResourceupdated(resourcegroup, vmname, "Microsoft.Compute/virtualMachines", finishedCallback);
};

var deleteResource = function(resourcegroup, name, type, finishedCallback) {
    azureCommand(["resource", "delete", resourcegroup, name, type, api_version, "--quiet"],
        function(err, msg) {
            if (!err) {
                finishedCallback(err, " getresource done");
                return;
            }
            if (msg.indexOf("Resource does not exist") > -1)
                finishedCallback(null, "ignore error: " + name + " not exist")
            else
                finishedCallback(err, msg);
        });
};


var getResource = function(resourcegroup, name, type, finishedCallback) {
  getCurrentSubscription({"id":""},function(err,id){
  doAzureResourceManage(id, resourcegroup, "/providers/"+type+"/" + name, "", "GET", api_version,
    //azureCommand(["resource", "show", resourcegroup, name, type, api_version, "--json"],
        function(err, msg) {
            if (!err) {
                var result = JSON.parse(msg);
                finishedCallback(err, result);
                return;
            }
            finishedCallback(err, msg);
        });
  });
};



var attachVMDisk = function(resourcegroup, vmname, vm, vhd, finishedCallback) {
    var property = vm.properties;
    var lun = -1;
    for (var i = 0; i < 128; i++) {
        if (property.storageProfile.dataDisks.filter(function(d) {
                return d.lun == i;
            }).length == 0) {
            lun = i;
            break;
        }
    }
    var disk = {
        "vhd": {
            "uri": vhd
        },
        "name": "disk_" + (new Date).getTime(),
        "lun": lun,
        "createOption": "attach"
    };
    property.storageProfile.dataDisks.push(disk);
    azureCommand(["resource", "set", resourcegroup, vmname,
        "Microsoft.Compute/virtualMachines", JSON.stringify(property), api_version
    ], finishedCallback);
};

var updateTag = function(resourcegroup, name, type, resource, tag, finishedCallback) {
    var property = resource.properties;
    azureCommand(["resource", "set", resourcegroup, name, type, "-t", tag,
        JSON.stringify(property), api_version
    ], finishedCallback);
};


var setIPlabelName = function(resourcegroup,  ip, labelname, finishedCallback) {

    azureCommand(["resource", "show", resourcegroup, ip, "Microsoft.Network/publicIPAddresses", api_version, "--json"],
        function(err, msg) {
            if (err) {
                finishedCallback(err, msg);
                return;
            }
            var property = JSON.parse(msg);

            property.properties.dnsSettings = {
                "domainNameLabel": labelname
            };
            delete property.provisioningState
            delete property.permissions
            doAzureResourceManage(property.id.split("/")[2], resourcegroup, "/providers/microsoft.network/publicIPAddresses/" + ip, '', 'PUT', api_version, finishedCallback, JSON.stringify(property));
        });
        
};
var bindIP = function(resourcegroup, nicname, ip, finishedCallback) {

    azureCommand(["resource", "show", resourcegroup, ip, "Microsoft.Network/publicIPAddresses", api_version, "--json"],
        function(err, msg) {
            if (err) {
                finishedCallback(err, msg);
                return;
            }
            var ipconfigid = JSON.parse(msg).id;
            azureCommand(["resource", "show", resourcegroup, nicname, "Microsoft.Network/networkInterfaces", api_version, "--json"],
                function(err, msg) {
                    if (err) {
                        finishedCallback(err, msg);
                        return;
                    }
                    var property = JSON.parse(msg);

                    property.properties.ipConfigurations[0].properties.publicIPAddress = {
                        "id": ipconfigid
                    };
                    delete property.provisioningState
                    delete property.permissions
                    doAzureResourceManage(ipconfigid.split("/")[2], resourcegroup, "/providers/microsoft.network/networkInterfaces/" + nicname, '', 'PUT', api_version, finishedCallback, JSON.stringify(property));
                });
        });

};

var addSecurityGroup = function(resourcegroup, nicname, group, finishedCallback) {

    azureCommand(["resource", "show", resourcegroup, group, "Microsoft.Network/networkSecurityGroups", api_version, "--json"],
        function(err, msg) {
            if (err) {
                finishedCallback(err, msg);
                return;
            }
            var id = JSON.parse(msg).id;
            azureCommand(["resource", "show", resourcegroup, nicname, "Microsoft.Network/networkInterfaces", api_version, "--json"],
                function(err, msg) {
                    if (err) {
                        finishedCallback(err, msg);
                        return;
                    }
                    var property = JSON.parse(msg);

                    property.properties.networkSecurityGroup= {
                        "id": id
                    };
                    delete property.provisioningState
                    delete property.permissions
                    doAzureResourceManage(id.split("/")[2], resourcegroup, "/providers/microsoft.network/networkInterfaces/" + nicname, '', 'PUT', api_version, finishedCallback, JSON.stringify(property));
                });
        });

};


var dettachVMDisk = function(resourcegroup, vmname, vm, vhd, finishedCallback) {
    var property = vm.properties;
    _log("remove" + vhd);
    var newdisks = property.storageProfile.dataDisks.filter(function(d) {
        return d.vhd.uri.indexOf(vhd) == -1;
    });
    property.storageProfile.dataDisks = newdisks;
    azureCommand(["resource", "set", resourcegroup, vmname, "Microsoft.Compute/virtualMachines",
        JSON.stringify(property), api_version
    ], finishedCallback);
};

var HOMEDIR = process.env[(process.platform == 'win32') ? 'USERPROFILE' : 'HOME'];
var getToken = function(subscriptionId) {
    var accessTokenPath = path.join(HOMEDIR, ".azure/accessTokens.json")
    if (fs.existsSync(accessTokenPath)) {
        var token = fs.readFileSync(accessTokenPath);
        token = JSON.parse(String(token));
        return token.filter(function(t) {
            return Date.parse(t.expiresOn) - (new Date()) > 0;
        });
    }
    else {
        var token = fs.readFileSync(path.join(HOMEDIR, ".azure/azureProfile.json"));
        token = JSON.parse(String(token)).subscriptions;
        return token.filter(function(t) {
            return t.isDefault && Date.parse(t.accessToken.expiresAt) - (new Date()) > 0;
        });
    }

};

var refreshTokenTask = function(finishedCallback) {
    if (getToken()[0] != null) {
        finishedCallback(null, "done");
        return;
    }
    azureCommand(["group", "list"], function(err, msg) {
        finishedCallback(err, "");
    });
};

var getCurrentSubscription = function(subscriptionId, finishedCallback) {
    var profilePath = path.join(HOMEDIR, ".azure/azureProfile.json")
    if (fs.existsSync(profilePath)) {
        var sb = fs.readFileSync(profilePath);
        sb = JSON.parse(String(sb));
        if(sb.subscriptions){
           subscriptionId.id= sb.subscriptions.filter(function(t) {
            return t.isDefault == true;
          })[0].id;
         finishedCallback(null, subscriptionId.id);
         return 
       }
    }
    azureCommand(["account", "list", "--json"], function(err, msg) {
        if (err) {
            finishedCallback(err, msg);
        }
        else {
            subscriptionId.id = JSON.parse(msg).filter(function(t) {
                return t.isDefault == true;
            })[0].id;
            finishedCallback(null, subscriptionId.id);
        }
    });
};


var doVMTask = function(subscriptionId, resourcegroup, name, op, method, finishedCallback) {
    doAzureResourceManage(subscriptionId, resourcegroup, '/providers/Microsoft.Compute/virtualMachines/' + name + "/", op, method, api_version, function(err, msg) {
        finishedCallback(err, msg);
    })
}

var doStorageAccontTask = function(subscriptionId, resourcegroup, name, op, method, finishedCallback) {
    doAzureResourceManage(subscriptionId, resourcegroup, '/providers/Microsoft.Storage/storageAccounts/' + name + "/", op, method, api_version, finishedCallback)
}

var doAzureResourceManage = function(subscriptionId, resourcegroup, name, op, method, api_version, finishedCallback, body) {
    //console.log(process.argv)

    //https: //management.azure.com/subscriptions/xxx/resourceGroups/xx/providers/Microsoft.Storage/storageAccounts/xx/listKeys?api-version=2014-12-01-preview
    var body_content = '{}'
    if (typeof(body) != 'undefined' && body) {
        body_content = body
    }
    var WebResource = common.WebResource;
    var httpRequest = new WebResource();
    httpRequest.method = method;
    httpRequest.headers = {};
    httpRequest.headers['Content-Type'] = 'application/json; charset=utf-8';
    httpRequest.url = 'https://management.azure.com/subscriptions/' + subscriptionId + '/resourceGroups/' + resourcegroup + '/' + name+"/" ;
    if(op&&op.length>0)
    httpRequest.url +=op
    var queryParameters = [];
    queryParameters.push('api-version=' + (api_version));
    if (queryParameters.length > 0) {
        httpRequest.url = httpRequest.url + '?' + queryParameters.join('&');
    }
    _log(httpRequest.url)
    httpRequest.headers['x-ms-version'] = '2014-04-01-preview';
    if (method == 'POST' || method == 'PUT') {
        httpRequest.body = body_content;
    }

    var restapi_task = function(bk){
      var token = getToken()[0].accessToken;
        if ((typeof token) != "string") {
          token = token.accessToken;
      }
      var resourceManagementClient = resourceManagement.createResourceManagementClient(
        new common.TokenCloudCredentials({
            subscriptionId: subscriptionId,
            token: token
        }));
    
      resourceManagementClient.pipeline(httpRequest, function(err, response, body) {
          bk(err, body);
      });
    }
    dotask = addRetry([restapi_task], 10)[0];
    dotask(finishedCallback);
     
};

var main = function() {
    var resourcegroup = argv.r;
    var task = argv.t;

    var tasks = [];
    tasks.push(
        function(callback) {
            refreshTokenTask(callback);
        }
    );
    _log("paramters " + argv._);
    switch (task) {
        case "deploy":
            var template = argv._[0];
            var subscriptionId = {
                "id": ""
            };
            tasks.push(
                function(callback) {
                    getCurrentSubscription(subscriptionId, callback);
                }
            );
            var deployname = {};

            tasks.push(function(callback) {
                var paramters = argv._[1];
                if (fs.existsSync(paramters)) {
                    paramters = fs.readFileSync(paramters);
                }
                else {
                    paramters = new Buffer(paramters, 'base64').toString('utf-8');
                }
                paramters = JSON.parse(paramters);
                if (!fs.existsSync(template)) {
                    callback(ABORT, "no such file or directory  " + template);
                    return;
                }
                waitDeploymentSuccess(function(cb) {
                    doDeploy(resourcegroup, template, paramters, deployname, subscriptionId.id, cb);
                }, subscriptionId.id, resourcegroup, deployname, callback);
            });
            break;
        case "setTag":
            var resourcename = argv._[0];
            var resourcetype = argv._[1];
            var tag = argv._[2];
            var resource = {};
            tasks.push(
                function(callback) {
                    getResource(resourcegroup, resourcename, resourcetype, function(err, result) {
                        if (!err) {
                            resource = result;
                        }
                        callback(err, result);
                    });
                });
            tasks.push(
                function(callback) {
                    updateTag(resourcegroup, resourcename, resourcetype, resource, tag, callback);
                });
            break;
        case "findResource":
            var propertyid = argv._[0];
            var v = argv._[1];
            var type = argv._[2];
            var resource = []
            tasks.push(
                function(callback) {
                    findResource(resourcegroup, type, propertyid, v, resource, function(err, msg) {
                        resource.forEach(function(r) {
                            _result(r.name);
                        })

                        callback(err, msg);
                    });
                }
            );
            break;
        case "storagekey":
            var name = argv._[0];
            var subscriptionId = {
                "id": ""
            };
            tasks.push(
                function(callback) {
                    getCurrentSubscription(subscriptionId, callback);
                }
            );
            tasks.push(
                function(callback) {
                    doStorageAccontTask(subscriptionId.id, resourcegroup, name, 'listKeys', 'POST', function(err, msg) {
                        if (!err)
                            _result(JSON.parse(msg).key1);

                        callback(err, msg);
                    });
                }
            );

            break;
        case "delete":
            var resourcename = argv._[0];
            var resourcetype = argv._[1];
            tasks.push(
                function(callback) {
                    deleteResource(resourcegroup, resourcename, resourcetype, callback);
                });
            tasks.push(
                function(callback) {
                    azureCommand(["resource", "list", "-g", resourcegroup, "--json", "-r", resourcetype], function(err, msg) {
                        if (err) {
                            callback(err, msg);
                            return;
                        }
                        else if (msg.length > 0) {
                            var o = JSON.parse(msg).filter(function(t) {
                                return t.name == resourcename
                            });
                            if (o.length != 0) {
                                callback(RETRY, "resource not deleted");
                            }
                            else {
                                callback(null, "resouce deleted");
                            }
                        }
                        else {
                            callback(null, "resouce deleted");
                        }
                    })
                });
            break;
        case "addsecuritygroup":
            var nicname = argv._[0];
            var groupname = argv._[1];

            tasks.push(
                function(callback) {
                   addSecurityGroup(resourcegroup, nicname, groupname, callback);
                }
            );

            tasks.push(
                function(callback) {
                    waitResourceupdated(resourcegroup, nicname, "Microsoft.Network/networkInterfaces", callback);
                }
            );

            break;
        case "bindip":
            var ipname = argv._[0];
            var nicname = argv._[1];

            tasks.push(
                function(callback) {
                    bindIP(resourcegroup, nicname, ipname, callback);
                }
            );

            tasks.push(
                function(callback) {
                    waitResourceupdated(resourcegroup, nicname, "Microsoft.Network/networkInterfaces", callback);
                }
            );

            break;
         case "createip":
            var ipname = argv._[0];
            var labelname = argv._[1];
            tasks.push( 
                function(callback) {
                    azureCommand(["group","list","--json"],function(err,msg){
                       if(err){callback(err,msg);return}
                       var location = JSON.parse(msg).filter(function(t){return t.name==resourcegroup})[0].location
                       azureCommand(["resource","create",resourcegroup,"-n",ipname,"Microsoft.Network/publicIPAddresses",location,"2014-12-01-preview",
                    "-p",'{}'],callback);
                    });
                }
            );
            if(labelname&&labelname.length>0)
            {
            tasks.push(
                function(callback) {
                    setIPlabelName(resourcegroup, ipname, labelname, callback);
                }
            );
            }
            break;
        case "stop":
        case "start":
        case "restart":
            var vmname = argv._[0];
            var subscriptionId = {
                "id": ""
            };
            tasks.push(
                function(callback) {
                    getCurrentSubscription(subscriptionId, callback);
                }
            );
            tasks.push(
                function(callback) {
                    doVMTask(subscriptionId.id, resourcegroup, vmname, task, 'POST', callback);
                }
            );

            break;
        case "getlocation":
          tasks.push(
                function(callback) {
                    azureCommand(["group","list","--json"],function(err,msg){
                        if(!err){
                        var location = JSON.parse(msg).filter(function(t){return t.name==resourcegroup})[0].location;
                        _result(location);
                       }
                        callback(err,"Find resource group");
                });
               });
        break
        case "get":
            var name = argv._[0];
            var type = argv._[1]

            tasks.push(
                function(callback) {
                    getResource(resourcegroup, name, type, function(error, result) {
                        if (!error)
                            _result(JSON.stringify(result));
                        callback(error, result);
                    });
                });
            break;
        case "query":
            var vmname = argv._[0];
            var subscriptionId = {
                "id": ""
            };
            tasks.push(
                function(callback) {
                    getCurrentSubscription(subscriptionId, callback);
                }
            );
            tasks.push(
                function(callback) {
                    doVMTask(subscriptionId.id, resourcegroup, vmname, 'instanceview', 'GET', function(error, result) {
                        if (!error)
                            _result(result);
                        callback(error, result);
                    });
                });

            break;
        case "adddisk":
            var vmname = argv._[0];
            var uri = argv._[1];
            var resource = {};
            tasks.push(
                function(callback) {
                    getResource(resourcegroup, vmname, "Microsoft.Compute/virtualMachines", function(err, result) {
                        if (!err) {
                            resource = result;
                        }
                        callback(err, result);
                    });
                });
            tasks.push(
                function(callback) {
                    waitVMupdated(resourcegroup, vmname, callback);
                });
            tasks.push(
                function(callback) {
                    attachVMDisk(resourcegroup, vmname, resource, uri, callback);
                });
            tasks.push(
                function(callback) {
                    waitVMupdated(resourcegroup, vmname, callback);
                });

            break;
        case "rmdisk":
            var vmname = argv._[0]
            var vhduri = argv._[1]
            var resource = {};
            tasks.push(
                function(callback) {
                    getResource(resourcegroup, vmname, "Microsoft.Compute/virtualMachines", function(err, result) {
                        if (!err) {
                            resource = result;
                        }
                        callback(err, result);
                    });
                });

            tasks.push(
                function(callback) {
                    dettachVMDisk(resourcegroup, vmname, resource, vhduri, callback);
                });
            tasks.push(
                function(callback) {
                    waitVMupdated(resourcegroup, vmname, callback);
                });

            break;
        default:
            tasks.push(
                function(callback) {
                    callback("unknown command", "unkown command")
                }
            );

    }

    tasks = addRetry(tasks, task == "deploy" ? 60 : 20)
    var async = require('async')
    _log("There are " + tasks.length + " Tasks")
    async.series(tasks,
        function(error, result) {

            if (error) {
                _log("Task Failed in main with error " + JSON.stringify(error) + " " + result);
            }
            else {
                _log("Task Finished" + result);
            }
            _log("##RESULTBEGIN##")
            _log(JSON.stringify({
                "R": _resultStr,
                "Failed": error
            }));
            _log("##RESULTEND##")
        });


};


main();

