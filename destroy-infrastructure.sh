#!/bin/bash

echo "##################################"
echo "# destroy-infrastructure.sh      #"
echo "##################################"

# --- Configurações ---
CLUSTER_NAME="observability-cluster"
K8S_CONTEXT="kind-$CLUSTER_NAME"
NAMESPACE="observability"

echo "🗑️  Iniciando destruição da infraestrutura local..."

# 1. Verificar se o cluster Kind existe antes de tentar deletar
if kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
    echo "🔥 Cluster '$CLUSTER_NAME' encontrado. Iniciando remoção..."
    
    # Tentativa amigável de limpar o namespace primeiro (ajuda a liberar travas de volume no Docker)
    echo "⏱️  Removendo namespace '$NAMESPACE' e seus recursos..."
    kubectl delete namespace "$NAMESPACE" --context "$K8S_CONTEXT" --timeout=30s 2>/dev/null || echo "⚠️ Namespace já estava ausente ou demorou a responder. Forçando destruição do cluster..."

    # Deleta o cluster Kind fisicamente do Docker
    kind delete cluster --name "$CLUSTER_NAME"
else
    echo "ℹ️  O cluster '$CLUSTER_NAME' não foi encontrado no Kind. Nada a fazer."
fi

# 2. Limpeza profunda de resíduos do Kubectl
echo "🧹 Limpando contextos órfãos do kubectl..."
kubectl config delete-context "$K8S_CONTEXT" 2>/dev/null
kubectl config delete-cluster "$K8S_CONTEXT" 2>/dev/null
kubectl config unset "users.$K8S_CONTEXT" 2>/dev/null

# 3. Validar se a limpeza funcionou
echo "🔍 Verificando containers residuais no Docker..."
CONTAINERS_VIVOS=$(docker ps -a --filter "label=io.x-k8s.kind.cluster=$CLUSTER_NAME" -q)

if [ -n "$CONTAINERS_VIVOS" ]; then
    echo "⚠️  Aviso: Containers fantasmas detectados. Forçando parada via Docker..."
    docker rm -f $CONTAINERS_VIVOS
fi

echo "--------------------------------------------------"
echo "✅ INFRAESTRUTURA TOTALMENTE DELETADA!"
echo "💻 Memória RAM e portas do localhost liberadas com sucesso."
echo "--------------------------------------------------"
