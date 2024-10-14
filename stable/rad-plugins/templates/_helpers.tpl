{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "rad-plugins.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "rad-plugins.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rad-plugins.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
RAD Security API access key env secret
*/}}
{{- define "rad-plugins.access-key-env-secret" -}}
- name: ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      {{ if .Values.rad.accessKeySecretNameOverride -}}
      name: {{ .Values.rad.accessKeySecretNameOverride }}
      {{ else -}}
      name: rad-access-key
      {{ end -}}
      key: access-key-id
- name: SECRET_KEY
  valueFrom:
    secretKeyRef:
      {{ if .Values.rad.accessKeySecretNameOverride -}}
      name: {{ .Values.rad.accessKeySecretNameOverride }}
      {{ else -}}
      name: rad-access-key
      {{ end -}}
      key: secret-key
{{- end -}}

{{/*
rad-bootstrap initContainer
*/}}
{{- define "rad-plugins.bootstrap-initcontainer" -}}
- name: rad-bootstrapper
  image: {{ .Values.bootstrapper.image.repository }}:{{ .Values.bootstrapper.image.tag }}
  imagePullPolicy: Always
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    capabilities:
      drop:
        - ALL
    privileged: false
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
  {{- if .Values.rad.seccompProfile.enabled }}
    seccompProfile:
      type: RuntimeDefault
  {{- end }}
  env:
    - name: AGENT_VERSION
      value: {{ .Values.bootstrapper.image.tag | quote }}
    - name: CHART_VERSION
      value: {{ .Chart.Version }}
    - name: API_URL
      value: {{ .Values.rad.apiUrl}}
    - name: CLUSTER_NAME
      value: {{ .Values.rad.clusterName }}
    - name: NAMESPACE
      value: {{ .Release.Namespace }}
    {{- if .Values.rad.awsSecretId }}
    - name: RAD_AWS_SECRET_ID
      value: {{ .Values.rad.awsSecretId }}
    {{- else }}
{{ include "rad-plugins.access-key-env-secret" . | indent 4 }}
    {{- end }}
  volumeMounts:
  - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
    name: api-token
    readOnly: true
  resources:
{{ toYaml .Values.bootstrapper.resources | indent 4 }}
{{- end -}}
