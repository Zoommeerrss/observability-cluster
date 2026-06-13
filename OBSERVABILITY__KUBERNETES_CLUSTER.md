# ☸️ Guia de Comandos: Cluster Kubernetes (Kind) no WSL para Obdervability com Prometheus, Opentelemetry e Grafana

## 📥 Instalação de Ferramentas (WSL/Ubuntu)

### 📦 Healm

1. 🛠️ Instale o **Helm** no WSL, execute os seguintes comandos sequencialmente no terminal do seu WSL para baixar e instalar o binário estável mais recente:

```bash
$ curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
```

2. 🛠️ Dê permissão de execução ao script

```bash
$ chmod 700 get_helm.sh
```

3. 🛠️ Execute o instalador (irá pedir sua senha do sudo)

```bash
$ sudo ./get_helm.sh
```

4. ⚠️ Use o código com cuidado. Para validar se a instalação foi bem-sucedida, verifique a versão executando:

```bash
$ helm version
```

5. 🚀 Execute os comandos abaixo, um de cada vez para instalar os recursos requeridos pelo Cluster de Obdervability

```bash
$ helm repo add open-telemetry https://github.io . #IMPORTANTE: tem que ter um ponto no final da linha
$ helm repo add prometheus-community https://github.io
$ helm repo add grafana https://github.io
$ helm repo update
```

7. 🛠️ Caso esses comandos dêem errado, tente via shell-script:

7.1. 🛠️ Crie um .sh e insira nele as linhas abaixo:

```bash
$ cat << 'EOF' > ./observability-tools-install.sh
#!/bin/bash

echo "🔄 Adicionando repositórios oficiais do Helm..."

# URLs oficiais e completas de cada projeto
helm repo add open-telemetry https://github.io || exit 1
helm repo add prometheus-community https://github.io || exit 1
helm repo add grafana https://github.io || exit 1

echo "📥 Atualizando índices locais do Helm..."
helm repo update

echo "✅ REPOSITÓRIOS CONFIGURADOS COM SUCESSO!"
EOF
```

7.2. 🛠️ Execute esse comando para limpar os caracteres ocultos do Windows do seu arquivo

```bash
$ sed -i 's/\r//' ./observability-tools-install.sh
```

7.3. 🛠️ Execute o .sh novamente

```bash
$ ./observability-tools-install.sh
```

### 📥 Levantando o cluster por automação

Para levantar o cluster precisamos ter 2 arquivos:

1. bootstrap.sh
2. observability-tools-install.sh

Para que o cluster seja levantado corretamente é preciso seguir a ordem de execução dos scripts conforme a ordem acima.

Para conseguir fazer esse trabalho, vamos criar os 2 arquivos necessários para levantar o cluster.

1. bootstrap.sh

Crie o arquivo com o mesmo nome e atribua privilégios de execução:

```bash
$ chmod +x bootstrap.sh
```

Edite-o adicionando o conteúdo abaixo:

```bash
#!/bin/bash

echo "##################################"
echo "# bootstrap.sh                   #"
echo "##################################"

# --- Configurações ---
CLUSTER_NAME="observability-cluster"
KIND_CONFIG="./kind-config.yaml"

# O Kind gera o nome do contexto juntando "kind-" com o nome do cluster
K8S_CONTEXT="kind-$CLUSTER_NAME"

echo "🏗️  Iniciando Bootstrap da Infraestrutura..."

# 1. Criar Cluster se não existir
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "☸️  Cluster '$CLUSTER_NAME' já está ativo."
else
    echo "🚀 Criando cluster '$CLUSTER_NAME' do zero..."
    kind create cluster --config "$KIND_CONFIG" || { echo "❌ Erro ao criar cluster"; exit 1; }
fi

# 🔄 Garantir o contexto correto do kubectl
echo "🔄 Alternando contexto do kubectl para '$K8S_CONTEXT'..."
kubectl config use-context "$K8S_CONTEXT" || { echo "❌ Erro ao mudar de contexto"; exit 1; }

echo "✅ BOOTSTRAP CONCLUÍDO!"
echo "--------------------------------------------------"
echo "🌐 Cluster de Observabilidade: $CLUSTER_NAME"
echo "🔌 Porta OTLP/gRPC Configurada: localhost:4317"
echo "✅ Pronto para receber os manifestos de observabilidade manualmente."
echo "--------------------------------------------------"
```

2. observability-tools-install.sh

Crie o arquivo com o mesmo nome e atribua privilégios de execução:

```bash
$ chmod +x observability-tools-install.sh
```

Edite-o adicionando o conteúdo abaixo:

```bash
#!/bin/bash

echo "##################################"
echo "# observability-tools-install.sh #"
echo "##################################"

# --- Configurações ---
CLUSTER_NAME="observability-cluster"
KIND_CONFIG="./kind-config.yaml"

# Caminhos para os manifestos YAML puros
PROMETHEUS_MANIFEST="./.settings/prometheus-service.yaml" # INTEGRADO AQUI
GRAFANA_MANIFEST="./.settings/grafana-service.yaml"
OTEL_CONFIG_MANIFEST="./.settings/otel-collector-config.yaml"
OTEL_SERVICE_MANIFEST="./.settings/otel-collector-service.yaml"
OTEL_MONITOR_MANIFEST="./.settings/otel-collector-monitor.yaml"

# URLs oficiais mantidas para o OpenTelemetry (Se decidir usar o Helm do OTel futuramente)
OTEL_HELM_URL="https://github.io"
K8S_CONTEXT="kind-$CLUSTER_NAME"

echo "🏗️  Iniciando Bootstrap da Infraestrutura..."

# 0. Sincronizar o relógio do sistema (WSL2)
echo "🕒 Sincronizando relógio do sistema no WSL2..."
if grep -qi microsoft /proc/version; then
    if ! command -v ntpdate &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq ntpdate > /dev/null 2>&1
    fi
    sudo ntpdate -s ://windows.com || sudo ntpdate -s pool.ntp.org
fi

# 1. Criar Cluster se não existir
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "☸️  Cluster '$CLUSTER_NAME' já está ativo."
else
    echo "🚀 Criando cluster '$CLUSTER_NAME'..."
    kind create cluster --config "$KIND_CONFIG" || { echo "❌ Erro ao criar cluster"; exit 1; }
fi

# 🔄 Garantir o contexto correto do kubectl
kubectl config use-context "$K8S_CONTEXT"

# 2. Criar o namespace de observabilidade
echo "🔄 Criando namespace 'observability'..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# 3. Remover resíduos antigos do Helm do Prometheus para liberar RAM
echo "🧹 Limpando instalações antigas do Helm para evitar conflitos..."
helm uninstall kube-stack -n observability 2>/dev/null
kubectl delete mutatingwebhookconfigurations --all 2>/dev/null
kubectl delete validatingwebhookconfigurations --all 2>/dev/null

# 4. Instalar o Prometheus via Manifesto Puro (Ultra-Leve)
echo "📥 Aplicando manifesto puro do Prometheus (Deployment/Service)..."
if [ -f "$PROMETHEUS_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$PROMETHEUS_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $PROMETHEUS_MANIFEST"
    exit 1
fi

# 4.1 Instalar o Grafana Customizado
echo "📥 Aplicando manifesto puro do Grafana (Deployment/Service)..."
if [ -f "$GRAFANA_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$GRAFANA_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $GRAFANA_MANIFEST"
    exit 1
fi

# 5. Instalar as configurações do OpenTelemetry Collector (ConfigMap)
echo "📥 Aplicando ConfigMap do OpenTelemetry Collector..."
if [ -f "$OTEL_CONFIG_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$OTEL_CONFIG_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $OTEL_CONFIG_MANIFEST"
    exit 1
fi

# 5.1 Instalar o OpenTelemetry Collector (Service/Deployment)
echo "📥 Aplicando manifesto do OpenTelemetry Collector..."
if [ -f "$OTEL_SERVICE_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$OTEL_SERVICE_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $OTEL_SERVICE_MANIFEST"
    exit 1
fi

# 6. Aguardar a inicialização dos serviços principais
echo "⏳ Aguardando os containers baixarem (Apenas 1 réplica de cada)..."
sleep 10

echo "🕒 Verificando status do Prometheus..."
kubectl wait --insecure-skip-tls-verify=true --for=condition=ready pod -l app=prometheus -n observability --timeout=120s

echo "🕒 Verificando status do Grafana..."
kubectl wait --insecure-skip-tls-verify=true --for=condition=ready pod -l app=grafana -n observability --timeout=120s

echo "🕒 Verificando status do OpenTelemetry Collector..."
kubectl wait --insecure-skip-tls-verify=true --for=condition=ready pod -l app=otel-collector -n observability --timeout=120s

echo "--------------------------------------------------"
echo "✅ INFRAESTRUTURA E STACK PRONTAS PARA USO!"
echo "🌐 Acesse o Prometheus localmente: http://localhost:9090"
echo "🌐 Acesse o Grafana localmente: http://localhost:3000 (NodePort: 32300)"
echo "🔌 Porta OTLP gRPC Ativa: localhost:4317 (NodePort: 30317)"
echo "🔌 Porta OTLP HTTP Ativa: localhost:4318 (NodePort: 30318)"
echo "📊 Métricas Internas do OTel sendo coletadas via ServiceMonitor!"
echo "🔐 Senha Padrão do Grafana: definida no seu manifesto personalizado"
echo "--------------------------------------------------"

```

Com os 2 arquivos prontos e com os privilégios necessários, basta seguir a ordem de execução:

1. execute o arquivo bootstrap.sh

```bash
$ ./bootstrap.sh
```

2. execute o arquivo observability-tools-install.sh

```bash
$ ./observability-tools-install.sh
```

✅ Ao final da execução de cada um deles o cluster deverá estar pronto para uso!

### 🔍 Troubleshooting Prometheus

- Verificando os pods e identificando seus nomes. 

⚠️ Isso é importante para a execução correta dos comandos a seguir do kubectl com o nome correto do pod

```bash
$ kubectl get pods -n observability
```

- Verificando os erros do Prometheus

```bash
$ kubectl describe pod prometheus-kube-stack-kube-prometheus-prometheus-0
```

- Verificando os logs do Prometheus no namespace

```bash
$ kubectl logs prometheus-kube-stack-kube-prometheus-prometheus-0 -n observability
```

- Verificando os eventos realizados

```bash
$ kubectl describe pod prometheus-kube-stack-kube-prometheus-prometheus-0 -n observability
```

- Executando o port-forward separadamente para testar a porta 9090 do Prometheus

```bash
# Opção mais provável para o Prometheus de desenvolvimento:
$ kubectl port-forward svc/kube-stack-kube-prometheus-prometheus 9090:9090 -n observability
```

```bash
# Alternativa comum criada pelo Operator:
$ kubectl port-forward svc/prometheus-operated 9090:9090 -n observability
```

⚠️ Depois de executar uma das 2 opções, vá até o browser pra ver se a porta 9090 (http://localhost:9090) está liberando a pagina do Prometheus

- Identificar o IP de todos os serviços no namespace

```bash
$ kubectl get svc -n observability
```

- Identificar o IP do Prometheus

```bash
$ kubectl get pods -n observability -l prometheus=kube-stack-kube-prometheus-prometheus -o wide
```


## 🧹 Limpeza do ambiente

- Deletando o cluster o namespace padrao

```bash
$ kind delete cluster --name observability-cluster
```

- Deletando o cluster o namespace gerado pelo kind no processo de bootstrap

```bash
$ kind delete cluster --name kind-observability-cluster
```

- Utilizando automação para deletar todo o cluster

```bash
$ ./destroy-infrastructure.sh
``` 