#!/usr/bin/env python3
"""
    python webhook api to FMGATEWAY for send alarm next to CFMS and SMS
"""
import requests
import os
import json
import sys
import logging
from pythonjsonlogger import jsonlogger
import datetime
from typing import Dict, Optional, List
import uvicorn
from fastapi import FastAPI, Request, Body ,Response , status, HTTPException, Depends
import sys
from prometheus_alert_model import main as prometheus_alert_model
from re import compile
from fastapi.responses import JSONResponse
import re
from pydantic import create_model

def init_logger():
    config = {
        'version': 1,
        'disable_existing_loggers': True,
        'formatters': {
            'json': {
                '()': jsonlogger.JsonFormatter, # without custom logs
                'format': '%(asctime)s %(levelname)s %(lineno)d %(message)s'
            },
        },
        'handlers': {
            'console_stdout': {
                # Sends log messages with log level lower than ERROR to stdout
                'class': 'logging.StreamHandler',
                'level': os.getenv("LOG_LEVEL") or 'INFO',
                'formatter': 'json',
                'stream': sys.stdout
            },
        },
        'root': {
                'level': os.getenv("LOG_LEVEL") or 'INFO',
                'handlers': ['console_stdout']
        }
    }
    logging.config.dictConfig(config)


def load_config():
    config = dict()

    loaded_mapping = os.getenv("SEVERITY_LEVEL_MAPPING")
    loaded_default_resolved_severity = os.getenv("DEFAULT_RESOLVE_SEVERITY")
    loaded_default_firing_severity = os.getenv("DEFAULT_FIRING_SEVERITY")
    loaded_fmgateway_url = os.getenv("FMGATEWAY_URL")
    loaded_fmgateway_request_timeout = os.getenv("FMGATEWAY_REQUEST_TIMEOUT")
    loaded_fmgateway_ssl_verify = os.getenv("FMGATEWAY_SSL_VERIFY")
    
    config["SEVERITY_MAPPING"] = json.loads(loaded_mapping) if loaded_mapping else {"critical": "critical", "warning": "major", "info": "minor", "none": "minor" }
    config["DEFAULT_FIRING_SEVERITY"] = loaded_default_firing_severity if loaded_default_firing_severity else "firing"
    config["DEFAULT_RESOLVE_SEVERITY"] = loaded_default_resolved_severity if loaded_default_resolved_severity else "clear"
    config["FMGATEWAY_URL"] = loaded_fmgateway_url if loaded_fmgateway_url else "" # TODO: ADD URL for this
    config["FMGATEWAY_REQUEST_TIMEOUT"] = loaded_fmgateway_request_timeout if type(loaded_fmgateway_request_timeout) == "float" else float(loaded_fmgateway_request_timeout) if loaded_fmgateway_request_timeout else 2.5
    config["FMGATEWAY_SSL_VERIFY"] = eval(loaded_fmgateway_ssl_verify) if loaded_fmgateway_ssl_verify else False

    return config


## init application 
init_logger()
logger = logging.getLogger()
app = FastAPI()

## pre-defined request parameters (and default value for FM gateway )
fm_query_params = {
    "module_name": (str, "StandardFormat"),
    "amo_name": (str, ""),
    "mc_zone": (str, ""),
    "node": (str, ""),
    "system_name": (str, ""),
    "ems_name": (str, ""),
    "ems_ip": (str, ""),
    "site_code": (str, ""),
    "region": (str, "BKK"),
    "node_ip": (str, ""),
    "network_type": (str, ""),    
}

fm_query_model = create_model("Query", **fm_query_params) # This is subclass of pydantic BaseModel

@app.on_event("startup")
async def startup_event():
    global config
    config = load_config()
    logger.info("Application is start")
    logger.info({"message": "Application Config", **config})

def remove_unnecessary_log_key(log):
    log.pop("timestamp")
    log.pop("client")
    log.pop("method")
    log.pop("request_path")
    log.pop("request_body_alert")

def map_fmgateway_severity_level(alert_status, severity):
    ## in case alert_status == "firing", mark as switcher 
    ## in case alert_status == "resolved", mark as "clear"
    ## in case alert_status can not match, mark as "critical"

    severity_mapping = config["SEVERITY_MAPPING"]
    default_firing_severity = config["DEFAULT_FIRING_SEVERITY"]
    default_resolved_severity =  config["DEFAULT_RESOLVE_SEVERITY"]

    return default_resolved_severity if alert_status == "resolved" else severity_mapping.get(severity, default_firing_severity) if alert_status == "firing" else default_firing_severity

@app.get("/health")
def health_check():
    content = {
        "status_code": "200",
        "message": "healthy"
        }
    return JSONResponse(status_code=200,content=content)

@app.post("/fmgateway")
def webhook_fmgateway(alert_group: prometheus_alert_model.AlertGroup, request: Request, params: fm_query_model = Depends()):
    params_as_dict = params.dict() 
    start_time = datetime.datetime.now()
    payloadFmGatewayList = []
    exceptionlist = []

    log = dict()
    log["timestamp"] = start_time.strftime("%Y-%m-%d %H:%M:%S")
    log["client"] = request.client.host
    log["method"] = request.method
    log["request_path"] = request.url.path
    log["request_body_alert"] = alert_group
    log["fmgateway_url"] = config["FMGATEWAY_URL"]
    log["alerts_count"] = len(alert_group.alerts) if alert_group.alerts else 0
    
    logger.info({"message": "Request Info", **log})

    alert_group.remove_re(
        annotations=r"^(__.*)$",
        labels=compile(r"^(__.*)$")
    )

    for alert in alert_group.alerts:

        payloadFmGateway = None

        try:
            ## get alert name 
            alert_name_val = alert.labels["alertname"]
            ## get severity level 
            severity_val = map_fmgateway_severity_level(alert.status, alert.labels["severity"])
            ## get additonal value from labels firsts, if labels is not exist get it from request parameter, standard value
            module_name_val = alert.labels["module_name"] if "module_name" in alert.labels.keys() else  params_as_dict["module_name"]
            amo_name_val = alert.labels["amo_name"] if "amo_name" in alert.labels.keys() else params_as_dict["amo_name"]
            mc_zone_val = alert.labels["mc_zone"] if "mc_zone" in alert.labels.keys() else params_as_dict["mc_zone"]
            node_val = alert.labels["node"] if "node" in alert.labels.keys() else params_as_dict["node"]
            system_name_val = alert.labels["system_name"] if "system_name" in alert.labels.keys() else params_as_dict["system_name"]
            ems_name_val = alert.labels["ems_name"] if "ems_name" in alert.labels.keys() else params_as_dict["ems_name"]
            ems_ip_val = alert.labels["ems_ip"] if "ems_ip" in alert.labels.keys() else params_as_dict["ems_ip"]
            site_code_val = alert.labels["site_code"] if "site_code" in alert.labels.keys() else params_as_dict["site_code"]
            region_val = alert.labels["region"] if "region" in alert.labels.keys() else params_as_dict["region"]
            node_ip_val = alert.labels["node_ip"] if "node_ip" in alert.labels.keys() else params_as_dict["node_ip"]
            network_type_val = alert.labels["network_type"] if "network_type" in alert.labels.keys() else params_as_dict["network_type"]
            ## form a namespace value and for attaching to the description field
            namespace_val = "namespace: {}".format(alert.labels["namespace"]) if "namespace" in alert.labels.keys() else ""   
                    
            ## convert description from alert.labels and alert.annotations
            alert_time_stamp = ""
            alert_time_stamp_label = ""
            alert_description = ""
            alert_summary = ""

            if alert.status == "firing" and hasattr(alert, 'starts_at'):
                alert_time_stamp = str(alert.starts_at)
                alert_time_stamp_label = "starts_at"
            if alert.status == "resolved" and hasattr(alert, 'starts_at'):
                alert_time_stamp = str(alert.starts_at)
                alert_time_stamp_label = "starts_at"
            if alert.status == "resolved" and hasattr(alert, 'ends_at'):
                alert_time_stamp = str(alert.ends_at)
                alert_time_stamp_label = "ends_at"
            
            if hasattr(alert, 'annotations') and 'description' in alert.annotations.keys():
                alert_description = alert.annotations['description']
            if hasattr(alert, 'annotations') and 'summary' in alert.annotations.keys():
                alert_summary = alert.annotations['summary']

            description_val = ""
            if(alert_description != ""): 
                description_val += "{}, ".format(alert_description)
            if(namespace_val != ""): 
                description_val += "{}, ".format(namespace_val)
            if(alert_time_stamp_label != ""): 
                description_val += "{}, ".format(alert_time_stamp_label)
            if(alert_time_stamp != ""): 
                description_val += "{}, ".format(alert_time_stamp)

            description_val = description_val[0:-2]
            payloadFmGateway = {
                    "module": module_name_val,
                    "amoName": amo_name_val,
                    "alarmName": alert_name_val,
                    "description": description_val,
                    "node": node_val,
                    "mcZone": mc_zone_val,
                    "systemName": system_name_val,
                    "emsName": ems_name_val,
                    "emsIp": ems_ip_val,
                    "siteCode": site_code_val,
                    "severity": severity_val,
                    "region": region_val,
                    "nodeIp": node_ip_val,
                    "networkType": network_type_val
                }
            headers = {
                "Accept": "application/json",
                "Content-type": "application/json"
            }
            auth = requests.auth.HTTPBasicAuth(os.getenv("RESTGW_USER"), os.getenv("RESTGW_PWD"))
            try:    
                print("PayLoad FMGateway")
                print(payloadFmGateway)
                resp = requests.post(config["FMGATEWAY_URL"], auth=auth, json=payloadFmGateway, timeout=config["FMGATEWAY_REQUEST_TIMEOUT"], verify=config["FMGATEWAY_SSL_VERIFY"], headers=headers) 
                resp.raise_for_status()
                response_message = str(json.loads(resp.text))
                payloadFmGatewayList.append(payloadFmGateway)
                success_body = {"alarmName": alert.labels["alertname"], "fingerprint": alert.fingerprint, "fm_payload": payloadFmGateway,"fm_response": response_message}
                logger.info({"message": "Success", **success_body})
            except requests.exceptions.RequestException as err:
                err_str = "FM Request Error"
                err_body = {"alarmName": alert.labels["alertname"], "error": err_str , "fingerprint": alert.fingerprint, "details": str(err), "fm_payload": payloadFmGateway}
                exceptionlist.append(err_body)
                logger.error({"message": "Error", **err_body})
            except requests.exceptions.HTTPError as err:
                err_str = "FM Http Error"
                err_body = {"alarmName": alert.labels["alertname"], "error": err_str , "fingerprint": alert.fingerprint, "details": str(err), "fm_payload": payloadFmGateway}
                exceptionlist.append(err_body)
                logger.error({"message": "Error", **err_body})
            except requests.exceptions.ConnectionError as err:
                err_str = "FM Error Connecting"
                err_body = {"alarmName": alert.labels["alertname"], "error": err_str , "fingerprint": alert.fingerprint, "details": str(err), "fm_payload": payloadFmGateway}
                exceptionlist.append(err_body)
                logger.error({"message": "Error", **err_body})
            except requests.exceptions.Timeout as err:
                err_str = "FM Timeout Error"
                err_body = {"alarmName": alert.labels["alertname"], "error": err_str , "fingerprint": alert.fingerprint, "details": str(err), "fm_payload": payloadFmGateway}
                exceptionlist.append(err_body)
                logger.error({"message": "Error", **err_body})
            except Exception as err: 
                err_str = "FM Unknown Exception"
                err_body = {"alarmName": alert.labels["alertname"], "error": err_str , "fingerprint": alert.fingerprint, "details": str(err), "fm_payload": payloadFmGateway}
                exceptionlist.append(err_body)
                logger.error({"message": "Error", **err_body})

        except Exception as e:
            err_str = "Error"
            err_body = {"alarmName": alert.labels["alertname"], "error": err_str , "fingerprint": alert.fingerprint, "details": str(err), "fm_payload": payloadFmGateway}
            exceptionlist.append(err_body)
            logger.error({"message": "Error", **err_body})

    delta_time = datetime.datetime.now() - start_time
    response_time = int(delta_time.total_seconds() * 1000)
    response_body = log
    response_body["response_time"] = response_time
    
    if(len(exceptionlist)>0):
        remove_unnecessary_log_key(response_body)

        response_body["status"] = "error"
        response_body["errors"] = exceptionlist

        return JSONResponse(content=response_body, status_code=500)
    
    remove_unnecessary_log_key(response_body)
    response_body["status"] = "success"
