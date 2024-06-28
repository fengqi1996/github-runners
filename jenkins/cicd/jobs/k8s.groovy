#!/usr/bin/env groovy

pipelineJob('k8s-e2e') {
    displayName('CCE SWR CI Pipeline')

    logRotator {
        numToKeep(10)
        daysToKeep(30)
    }

    configure { project ->
        project / 'properties' / 'org.jenkinsci.plugins.workflow.job.properties.DurabilityHintJobProperty' {
            hint('PERFORMANCE_OPTIMIZED')
        }
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/oversampling/github-runners.git')
                        credentials('github-username-password')
                    }
                    branches('*/main')
                }
            }
            scriptPath('jenkins/cicd/pipelines/k8s.groovy')
        }
    }
}