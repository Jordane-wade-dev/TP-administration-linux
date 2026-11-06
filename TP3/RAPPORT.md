# TP3 : Pare-feu, SSH et surveillance des journaux

Étudiante : Jordane  
Environnement : Rocky Linux 9.8 sur srv-core et srv-edge

## 1. Configuration du pare-feu

| Interface | Zone | Pourquoi |
|---|---|---|
| enp0s3 | drop | C’est l’interface NAT. Je n’ai pas besoin d’y ouvrir de service entrant. |
| enp0s8 | work | C’est le réseau d’administration. J’y autorise SSH avec une limite de débit et je rejette le port 10051. |
| bond0 et bond0.42 | internal | Le réseau métier et le VLAN transport ont besoin de SSH et du port 10051 pour la supervision. |

J’ai mis drop comme zone par défaut. Au premier scan depuis srv-edge, le port 22 était ouvert, le port 80 était filtré et le port 10051 apparaissait fermé. Quand j’ai lancé plusieurs connexions sur le port 22 à la suite, les premières sont passées, puis certaines ont été refusées ou ont expiré. Sur srv-core, les lignes SSH-NEW indiquaient bien l’adresse source de srv-edge (192.168.56.11) et le port 22.

## 2. Sécurisation de SSH

J’ai d’abord vérifié que je pouvais me connecter par clé depuis srv-edge. Pour passer au port 2242, j’ai changé le port d’écoute de sshd, ajouté ce port au type ssh_port_t dans SELinux, puis ouvert le port dans firewalld. Une fois la connexion par clé testée sur le nouveau port, j’ai retiré les anciennes règles pour le port 22.

Pendant les tests, sysops a pu se connecter par clé. L’ancien port n’était plus accessible, la connexion root et l’authentification par mot de passe ont été refusées, et Nadia n’a pas pu se connecter. La redirection TCP demandée par sysops a aussi été refusée. Quand j’ai forcé un échange de clés SHA-1, le client et le serveur n’ont pas trouvé d’algorithme commun.

Le fichier 50-redhat.conf charge la politique cryptographique du système. Comme sshd garde la première valeur lue pour les options testées, j’ai placé mes réglages dans 05-helios-crypto.conf, qui est lu avant. J’ai ensuite vérifié les valeurs prises en compte avec `sshd -T`.

## 3. Journaux et audit

J’ai activé le stockage persistant des journaux, puis redémarré srv-core. Après le redémarrage, j’ai pu retrouver des messages du démarrage précédent.

| Requête utilisée | Ce que j’ai cherché |
|---|---|
| `journalctl -u sshd.service --since '-2h' -p warning` | Les avertissements et erreurs SSH des deux dernières heures. |
| `journalctl -u sshd.service -g 'Invalid user\|Failed\|Accepted\|not allowed'` | Les connexions SSH acceptées, les échecs et les refus. |
| `journalctl --facility=authpriv --since today` | Les messages d’authentification enregistrés depuis minuit. |
| `journalctl -t sudo --since today -o json-pretty` | Les événements sudo et leurs détails. J’y ai retrouvé la commande qui liste les démarrages. |
| `journalctl -b -1 -p err` | Les erreurs du démarrage précédent. J’y ai retrouvé les trois essais de mot de passe sudo incorrects de sysops. |

Pour tester auditd, j’ai créé puis supprimé le fichier /etc/sudoers.d/test-audit. Les deux actions apparaissent dans le journal d’audit. J’ai aussi lancé helios-lastlog avec Julien et vérifié que l’exécution avait été enregistrée avec telemetry comme groupe effectif.

## 4. Blocage automatique

Le script compte les échecs SSH par adresse IP sur les dix dernières minutes. Au-delà de cinq échecs, il ajoute l’adresse à la liste de blocage. L’adresse 192.168.56.1 est exemptée et un verrou empêche deux instances du script de tourner en même temps.

Au premier essai, je n’avais que deux événements « Invalid user pirate » et la liste était encore vide. J’ai relancé les tentatives en les espaçant pour qu’elles atteignent le serveur malgré la limite du pare-feu. Cette fois, l’adresse 192.168.56.11 est apparue dans la liste et le journal a indiqué 14 échecs sur les dix dernières minutes.

J’ai retiré l’adresse de la liste après le test et différé le démarrage du timer pour éviter qu’elle soit bloquée de nouveau à cause des mêmes tentatives. Le timer est réglé pour lancer le script toutes les deux minutes. J’ai vérifié que le timer s’était déclenché et que la prochaine exécution était bien planifiée.
