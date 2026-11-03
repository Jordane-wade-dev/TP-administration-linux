# TP1:systemd, réseau avancé et automatisation



## 1. Environnement et choix techniques



J'ai réalisé ce TP sur une machine virtuelle Rocky Linux 9 (srv-core), installée avec VirtualBox sur mon ordinateur Windows.



Mon ordinateur hébergeait déjà plusieurs machines virtuelles Windows Server utilisées pour d'autres cours. Il ne me restait qu'environ 26 à 29 Go de stockage libre. J'ai donc privilégié une installation minimale de Rocky Linux et commencé par les missions réalisables avec une seule VM.



### Pourquoi PowerShell et SSH ?



J'ai choisi d'administrer la VM depuis Windows PowerShell en utilisant SSH :



```bash

ssh -p 2222 sysops@127.0.0.1

```



J'avais configuré une redirection du port 2222 de Windows vers le port SSH 22 de la VM. Cette solution me permettait d'exécuter les commandes Linux tout en restant sur mon environnement Windows et de transférer facilement les fichiers avec `scp`.



### Pourquoi sudo plutôt que root ?



Le support  utiliser dans le pdf est `root`. Pour ma part, j'ai travaillé avec l'utilisateur `sysops` et utilisé `sudo` lorsque des droits administrateur étaient nécessaires.



Par exemple, `sudo systemctl restart helios-collect.service` modifie l'état d'un service système, alors que `systemctl is-active helios-collect.service` permet simplement de consulter son état.



`sudo` exécute  la commande avec les mêmes privilèges que root mais évite de rester en session administrateur en permanence ce que je ne voulais pas faire. Certaines commandes ont donc été adaptées par rapport au support, sans changer leur objectif.



## 2. Mission 1 : Gestion des services systemd



### Service Helios et ressources



J'ai créé `helios-collect.service` pour exécuter un script collectant régulièrement des données dans `/var/lib/helios/telemetry.csv`.



J'ai vérifié son fonctionnement avec `systemctl` et testé son redémarrage automatique après un arrêt forcé du processus.



J'ai ensuite ajouté un fichier `override.conf` contenant notamment :



- `CPUQuota=20%`

- `MemoryMax=96M`

- `IOWeight=50`

- `Nice=5`



J'ai utilisé `systemd-cgls` et `systemd-cgtop` pour observer les processus et la consommation de ressources.



Le fichier d'override permet d'ajouter des paramètres sans modifier directement le fichier principal du service.



### Sécurisation



J'ai utilisé `systemd-analyze security` pour évaluer l'exposition du service. J'ai ensuite ajouté plusieurs protections, notamment `PrivateDevices=yes`, `ProtectKernelModules=yes`, `ProtectKernelLogs=yes`, `ProtectClock=yes`, `LockPersonality=yes` et `RestrictNamespaces=yes`.



| Analyse | Score |

|---|---|

| Avant | 5.3 – MEDIUM |

| Après | 3.8 – OK |



Après `systemctl daemon-reload` et le redémarrage du service, j'ai vérifié que la collecte continuait. L'objectif était d'améliorer la sécurité sans empêcher le service de fonctionner.



### Optimisation du démarrage



J'ai utilisé `systemd-analyze` pour mesurer le démarrage et `systemd-analyze plot` pour produire les graphiques.



| Mesure | Résultat |

|---|---:|

| Avant | 20.243 s |

| Après | 18.769 s |

| Gain | 1.474 s (environ 7,3 %) |



Pour cette comparaison, j'ai désactivé temporairement `firewalld` et masqué `NetworkManager-wait-online.service`. La commande `mask` empêche également d'autres unités de démarrer le service masqué.



Après le test, j'ai réactivé `firewalld`, vérifié que SSH était autorisé et confirmé que le collecteur Helios fonctionnait toujours. Le service d'attente réseau est resté masqué.



Les deux graphiques sont disponibles dans `captures/`.



## 3. Mission 2 – Réseau avancé



Je n'ai pas encore réalisé la partie bonding, VLAN et routage.



La principale difficulté a été la capacité de stockage de mon ordinateur : les VM déjà présentes limitaient la possibilité de préparer immédiatement l'environnement réseau prévu. J'ai donc décidé de terminer et documenter les missions 1 et 3 en priorité plutôt que de risquer de manquer de temps pour le rendu.



## 4. Mission 3 : Automatisation de l'archivage



### Installation du script et difficultés rencontrées



J'ai installé `helios-archive.sh` dans `/usr/local/sbin/` avec des permissions restrictives (`0750`).



J'ai rencontré plusieurs difficultés :



- \*\*Outil manquant :\*\* la commande `tar` n'était pas installée dans mon Rocky Linux minimal. J'ai résolu le problème avec `sudo dnf install -y tar`.

- \*\*Chemin de fichier incorrect :\*\* lors d'un transfert `scp`, je cherchais le script dans `Downloads\\annexes`, alors qu'il se trouvait dans `Downloads\\annexes\\annexes`. Une recherche récursive avec `Get-ChildItem` m'a permis de retrouver le bon chemin.

- \*\*Permissions :\*\* l'exécution de `bash -n` sur le script installé renvoyait `Permission denied`. J'ai compris que le fichier appartenait à root avec des droits limités et j'ai effectué la vérification avec `sudo`.



### Tests des codes de retour



J'ai testé trois situations :



| Code | Situation observée |

|---|---|

| 0 | Archivage réalisé avec succès |

| 2 | Une autre exécution détient déjà le verrou |

| 3 | Fichier de télémétrie absent |



Pour tester le code 2, j'ai simulé un verrou déjà occupé avec `flock`. Pour le code 3, j'ai arrêté temporairement le collecteur et déplacé `telemetry.csv`, puis restauré le fichier et redémarré le service.



Ces tests m'ont permis de vérifier le comportement du script en fonctionnement normal et en cas d'erreur.



### Pourquoi un timer systemd plutôt que cron ?



J'ai installé `helios-archive.service` et `helios-archive.timer`, avec une exécution prévue autour de 02h30 et un délai aléatoire possible.



J'ai aussi configuré temporairement une tâche cron à la même heure pour comparer les deux solutions.



| Critère | Cron | Timer systemd |

|---|---|---|

| Configuration | Expression horaire | Unités service et timer |

| Journaux | Journaux cron | `journalctl` |

| État et prochaine exécution | Suivi moins direct | `systemctl list-timers` |

| Exécution manquée | Pas de rattrapage natif | `Persistent=yes` |



J'ai conservé le timer systemd, car il s'intègre aux services, facilite la consultation des journaux et permet de tester manuellement l'archivage. Le lancement manuel a réussi avec le code 0.



La tâche cron temporaire a ensuite été supprimée pour éviter les doublons. Je n'ai pas attendu 02h30 pour observer son exécution réelle.



## 5. Bilan



Ce TP m'a permis de mieux comprendre le fonctionnement de systemd, la gestion des permissions, la limitation des ressources et l'automatisation sous Linux.



Les difficultés les plus concrètes ont concerné les limites matérielles de mon ordinateur, les chemins de fichiers entre Windows et Linux, les outils absents d'une installation minimale et les droits d'accès.



J'ai surtout appris à vérifier les résultats des commandes, à interpréter les erreurs et à adapter les instructions du support à mon environnement. Les missions 1 et 3 ont été testées ; la mission 2 reste à compléter.



