# Bloqueio de IPs Postfix

Script interativo em `dialog` que varre o log do Postfix em busca de
hostnames que terminam em um TLD específico, extrai os IPs IPv4
associados, e opcionalmente aplica esses IPs no bloqueio do Postfix
(`/etc/postfix/local_ipblacklist`), executando comandos de pós-processamento.

<img width="797" height="418" alt="image" src="https://github.com/user-attachments/assets/4ee3e8ce-2a1e-4466-a891-336e8cfbd352" />

<img width="719" height="765" alt="image" src="https://github.com/user-attachments/assets/2dcd387d-24c9-4fb1-a822-1b9046a61f65" />



---

## 📋 Índice

1. [Visão geral](#-visão-geral)
2. [Requisitos](#-requisitos)
3. [Instalação](#-instalação)
4. [Como usar](#-como-usar)
5. [Fluxo da interface](#-fluxo-da-interface)
6. [Como funciona internamente](#-como-funciona-internamente)
7. [Configurações](#-configurações)
8. [Arquivos manipulados](#-arquivos-manipulados)
9. [Aplicação no Postfix](#-aplicação-no-postfix)
10. [Comandos customizáveis](#-comandos-customizáveis)
11. [Exemplos de uso](#-exemplos-de-uso)
12. [Solução de problemas](#-solução-de-problemas)

---

## 🎯 Visão geral

O script automatiza o ciclo completo de:

- **Coleta** — varre o log do Postfix procurando conexões cujo hostname
  termine com um TLD escolhido pelo usuário (ex.: `.cf`, `.envios.cf`).
- **Extração** — obtém o IP IPv4 entre colchetes no log (IPv6 é ignorado).
- **Acúmulo** — grava os IPs em um arquivo-texto persistente, **sem
  sobrescrever** o que já existe (append + deduplicação).
- **Aplicação** — opcionalmente reescreve o arquivo de bloqueio do Postfix
  (`/etc/postfix/local_ipblacklist`) com todos os IPs coletados + a
  mensagem de `REJECT` configurada.
- **Pós-processamento** — executa até **5 comandos** customizáveis (ex.:
  `postmap`, `systemctl reload postfix`, `postfix check`) e exibe o
  resultado de cada um em verde/vermelho.

---

## ✅ Requisitos

| Item | Detalhes |
|------|----------|
| Sistema | Linux (Debian, Ubuntu, RHEL, CentOS, Alma, Rocky, etc.) |
| Shell | `bash` 4.0+ |
| Permissões | `root` (necessário para escrever em `/etc/postfix/` e rodar `systemctl`) |
| Dependências | `dialog`, `grep`, `sed`, `sort`, `postfix` (para aplicar) |

Instalação do `dialog`:

```bash
# Debian/Ubuntu
sudo apt install dialog

# RHEL/CentOS/Alma/Rocky
sudo dnf install dialog
