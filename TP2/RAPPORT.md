# TP2 — Permissions avancées et gestion des accès

**Étudiante :** Jordane  
**Environnement :** Rocky Linux 9, `srv-core`

## 1. ACL : droits affichés et droits effectifs

Le test a été réalisé sur `/srv/helios/projets/transport/tournee-j2.csv`, avec une entrée ACL donnant `rwx` à Tarek.

| Test | Résultat de `getfacl` | Écriture par Tarek |
|---|---|---|
| ACL initiale | `user:tarek:rwx`, `mask::rwx` | Réussie |
| Après `chmod g-w` | `user:tarek:rwx #effective:r-x`, `mask::r-x` | Refusée |
| Après `setfacl -m m::rwx` | `user:tarek:rwx`, `mask::rwx` | Réussie |

L’entrée de Tarek ne change pas après `chmod g-w` : c’est le masque qui perd le droit d’écriture. Les droits effectifs passent donc à `r-x`. La restauration du masque à `rwx` permet de nouveau l’écriture.

Les ACL par défaut ont également été testées sur les nouveaux fichiers du dossier `transport`. Le compte `audit-ext` dispose de la lecture, mais la création de fichiers lui est refusée.

## 2. Héritage du groupe et suppression dans un dossier partagé

Deux créations de fichiers avec Tarek ont permis de comparer le comportement avec et sans setgid :

- Dans `/srv/helios/projets/transport`, configuré en `2770`, le fichier créé prend le groupe `transport`.
- Dans le dossier témoin sans setgid, le fichier prend le groupe principal de Tarek, `telemetry`.

Dans `/srv/helios/depot`, configuré en `1777`, Tarek ne peut pas supprimer le fichier de Nadia malgré les droits d’écriture sur le dossier. La commande renvoie « Opération non permise ».

Après retrait temporaire du sticky bit, la suppression réussit. Le mode `1777` a été rétabli après le test.

## 3. Vérification des umask

| Umask | Fichier prévu | Fichier obtenu | Dossier prévu | Dossier obtenu |
|---|---|---|---|---|
| `027` | `640` | `640` | `750` | `750` |
| `002` | `664` | `664` | `775` | `775` |
| `077` | `600` | `600` | `700` | `700` |

Aucun écart entre les permissions prévues et observées.

Le réglage défini dans `/etc/profile.d/helios-umask.sh` a été vérifié avec Nadia et `audit-ext` : les membres de `transport` reçoivent l’umask `002`, les autres utilisateurs `027`.

## 4. Contrôle des privilèges

Avec Julien, les commandes autorisées sur `helios-collect.service` fonctionnent. La tentative de redémarrage de `sshd` est refusée (`rc=1`). Les traces d’exécution sont présentes dans les journaux sudo et consultables avec `sudoreplay -l`.

Le test de la règle temporaire autorisant Nadia à exécuter Vim comme root a permis de lancer `id` depuis l’éditeur. Le résultat `uid=0(root)` confirme l’obtention des privilèges root. Cette règle a été supprimée ; la configuration restante utilise `sudoedit` et a été validée avec `visudo -c`.

Le script Bash portant le bit setuid n’a pas permis d’obtenir les privilèges root. Pour le programme C `helios-lastlog`, installé en `2755` avec le groupe `telemetry`, Julien peut consulter les dernières lignes du journal. La même lecture avec `tail` est refusée.

## 5. Comptes et authentification

La politique appliquée impose une durée maximale de 90 jours, un délai minimal de 1 jour et un avertissement 14 jours avant expiration. Les nouveaux mots de passe doivent comporter au moins 12 caractères et trois classes de caractères.

Le verrouillage après cinq échecs a été testé avec `pam_faillock`. Le compte a ensuite été déverrouillé et l’accès rétabli.
