// Jenkins job SkipOS-CI (inline pipeline). Source of truth: this file in g7-infra.
// g7-drift compares the job with this file (MAP: job SkipOS-CI). Install or update it with the
// Jenkins CLI (create-job / update-job), as TaxGlasses' scripts/jenkins-jobs.ps1 does.
// A new job must be built once by hand: Jenkins registers the poll trigger only after a run.
//
// The unit lane only: no database, no Docker. The integration tests and the validate:* gates
// are left out on purpose (README in this folder says what they would need on G7).
// Credentials in Jenkins: 'g7-git-skipos' (read-only key from g7-new-repo.sh), 'ntfy-token'.

def NTFY_TOPIC = 'sites'   // ntfy topic for this project's alerts

def notify(String topic, String title, String msg, String prio = 'default', String tags = '') {
  // Phone alert through ntfy on G7. Never fails the build.
  try {
    withCredentials([string(credentialsId: 'ntfy-token', variable: 'NTFY_TOKEN')]) {
      withEnv(["NTFY_TOPIC=${topic}", "NTFY_TITLE=${title}", "NTFY_MSG=${msg}", "NTFY_PRIO=${prio}", "NTFY_TAGS=${tags}", "NTFY_CLICK=${env.BUILD_URL ?: ''}"]) {
        sh '''curl -fsS -m 10 -o /dev/null -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $NTFY_TITLE" -H "Priority: $NTFY_PRIO" -H "Tags: $NTFY_TAGS" -H "Click: $NTFY_CLICK" -d "$NTFY_MSG" "http://127.0.0.1:2586/$NTFY_TOPIC" || echo "ntfy: not sent"'''
      }
    }
  } catch (err) {
    echo "ntfy: not sent (${err})"
  }
}

pipeline {
  agent { label 'g7-worker' }

  options {
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  triggers { pollSCM('H/2 * * * *') }

  environment {
    // Node 24, installed beside the system Node (g7-infra: g7/install-node24.sh).
    PATH = "/opt/node24/bin:${env.PATH}"
    // onnxruntime-node (from the embedder) downloads CUDA binaries on linux-x64 by default, and
    // the 1.21.0 GPU download returns 404. G7 has no GPU; the CPU binaries ship in the package.
    ONNXRUNTIME_NODE_INSTALL_CUDA = 'skip'
  }

  stages {
    stage('Checkout') {
      steps {
        git url: 'ssh://git@192.168.0.6:3333/srv/git/repos/SkipOS.git', branch: 'main', credentialsId: 'g7-git-skipos'
      }
    }
    stage('Install') {
      steps {
        sh 'node -v && npm ci --no-audit --no-fund'
      }
    }
    stage('Typecheck') {
      steps {
        sh 'nice -n 10 npm run typecheck'
      }
    }
    stage('Unit tests') {
      steps {
        // G7 has 7.5 GiB RAM shared with TaxGlasses, MemeSniper and Jenkins. Vitest would start
        // one worker per CPU (11 on G7); 3 matches the agent's 3 executors.
        sh 'nice -n 10 npm run test:unit -- --maxWorkers=3'
      }
    }
  }

  post {
    failure { script { notify(NTFY_TOPIC, "${env.JOB_NAME} failed", "Build ${env.BUILD_NUMBER} failed.", 'high', 'warning') } }
    fixed   { script { notify(NTFY_TOPIC, "${env.JOB_NAME} passing again", "Build ${env.BUILD_NUMBER} passed.", 'low', 'white_check_mark') } }
  }
}
